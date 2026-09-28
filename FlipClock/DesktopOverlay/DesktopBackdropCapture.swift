import AppKit
import CoreImage
import ScreenCaptureKit

/// Software equivalent of `NSVisualEffectView.behindWindow` blending, but
/// with a real, tunable Gaussian blur radius — `NSVisualEffectView`'s own
/// blur radius is fixed by the system material and isn't a public API, so
/// no amount of `.opacity()` on it can push the diffusion past what that
/// fixed radius produces.
///
/// Captures the **whole display** rather than just the window's own rect,
/// blurs it once, and hands each widget the sub-rect sitting behind it.
/// Capturing only the window's rect meant the glass was a snapshot of
/// wherever the widget used to be: drag it and the old location's wallpaper
/// came along for the ride until the next 5s refresh caught up, then popped
/// to the new one. Cropping a `CGImage` is effectively free (it references
/// the same pixels), so the crop can instead be redone on every window move
/// and the glass tracks the desktop exactly while dragging, with no capture
/// work per frame.
///
/// The expensive part — capture plus `CIGaussianBlur` over a full screen —
/// is shared across every widget on that display via `SharedBackdrop`, so
/// adding world clock widgets doesn't multiply it.
///
/// Requires Screen Recording permission (macOS prompts on first capture
/// attempt). If the user denies it, `image` just stays `nil` forever and
/// `WidgetGlassBackground` falls back to its `NSVisualEffectView` look —
/// there's no hard failure, only a softer diffusion.
///
/// Uses `SCScreenshotManager` (ScreenCaptureKit), not `CGWindowListCreateImage`
/// — confirmed the hard way that the latter is a dead API on this SDK: it
/// still compiles and returns a non-nil `CGImage` (so the old nil-check
/// never caught it), but that image is a flat placeholder color, not real
/// screen content, which silently turned the "frosted glass" widget into a
/// flat opaque-looking panel with none of the desktop's actual color or
/// detail showing through.
final class DesktopBackdropCapture: ObservableObject {
    @Published private(set) var image: CGImage?
    /// The same backdrop blurred much harder, for the dimmed look. Prepared
    /// alongside `image` so switching looks is an opacity crossfade between
    /// two ready images — animating a live SwiftUI blur across the whole
    /// panel instead cost enough GPU per frame that the fade visibly lagged
    /// the click and stuttered.
    @Published private(set) var dimmedImage: CGImage?

    /// Last full-display blurred backdrops this widget received. Held here so
    /// `publishCrop` can crop synchronously on the main thread while dragging
    /// — going back to the shared store for them would make every drag event
    /// an `await`, and the glass would lag the window by a frame or more.
    private var fullBackdrop: BackdropPair?

    private var timer: Timer?
    private var activeWindow: NSWindow?
    private var activeBlurRadius: CGFloat = 0
    private var activeDimmedBlurRadius: CGFloat = 0
    private var occlusionObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var captureTask: Task<Void, Never>?

    /// Whether a capture is worth doing right now — pulled out as a pure
    /// function (no window/system calls) so it's directly unit-testable.
    /// Screen capture + `CIGaussianBlur` was, by a wide margin, the single
    /// biggest CPU/GPU/battery cost anywhere in the app (already throttled
    /// once, from 1s to 5s, per the comment below) — but even at 5s it ran
    /// unconditionally forever, including the common case where the overlay
    /// sits fully covered by another app's window (it's deliberately
    /// layered below normal windows — see `OverlayWindowController`) and
    /// literally nobody can see the result. `occlusionState.contains(.visible)`
    /// is exactly the signal AppKit already tracks for "is any pixel of
    /// this window actually being composited to the screen" — false
    /// whenever it's fully covered, minimized, on another Space, or the
    /// display is asleep/locked.
    static func shouldCapture(occlusionState: NSWindow.OcclusionState) -> Bool {
        occlusionState.contains(.visible)
    }

    /// Refresh cadence. The capture is wallpaper-only, and wallpaper barely
    /// changes, so this is a slow safety net (dynamic/aerial wallpapers drift)
    /// rather than the main trigger — Space switches, display changes and the
    /// end of a drag refresh immediately. At the old 5s, a capture plus two
    /// full-screen blurs ran twelve times a minute for a picture that hadn't
    /// changed: by far the app's biggest battery cost. Stretched further under
    /// Low Power Mode. Pure so it's directly testable.
    static func refreshInterval(isLowPowerModeEnabled: Bool) -> TimeInterval {
        isLowPowerModeEnabled ? 180.0 : 60.0
    }

    /// Where `window` sits inside a full-display backdrop image, in that
    /// image's pixel space (top-left origin, Y down) — Cocoa screen
    /// coordinates are bottom-left origin, so the Y axis flips here.
    ///
    /// Pure, and separated out, because this is the part with the axis flip
    /// and the multi-display offset in it: the arithmetic worth testing
    /// without needing a real window or a real screen capture.
    static func cropRect(
        windowFrame: CGRect,
        screenFrame: CGRect,
        pixelScale: CGFloat,
        imageSize: CGSize
    ) -> CGRect? {
        let rect = CGRect(
            x: (windowFrame.minX - screenFrame.minX) * pixelScale,
            y: (screenFrame.maxY - windowFrame.maxY) * pixelScale,
            width: windowFrame.width * pixelScale,
            height: windowFrame.height * pixelScale
        )
        // A widget dragged past the edge of the display would otherwise ask
        // for pixels the capture doesn't contain, which `cropping(to:)`
        // answers with nil — dropping the glass entirely mid-drag.
        let clamped = rect.intersection(CGRect(origin: .zero, size: imageSize))
        return clamped.isNull || clamped.isEmpty ? nil : clamped
    }

    /// The wallpaper sits at or below `kCGDesktopWindowLevel`; desktop icons
    /// (Finder) start one level band above it and app windows far above.
    static func isWallpaperLayer(_ layer: Int) -> Bool {
        layer <= Int(CGWindowLevelForKey(.desktopWindow))
    }

    func start(window: NSWindow, blurRadius: CGFloat, dimmedBlurRadius: CGFloat) {
        stop()
        activeWindow = window
        activeBlurRadius = blurRadius
        activeDimmedBlurRadius = dimmedBlurRadius
        refresh(window: window)
        scheduleTimer(window: window)
        // If the window goes from covered to visible again between ticks
        // (the user closes/moves whatever was on top of it), refresh right
        // away instead of leaving a stale blur on screen for up to the
        // remainder of the current interval.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window, Self.shouldCapture(occlusionState: window.occlusionState) else { return }
            self.refresh(window: window)
        }
        // Fires continuously while the user drags. Deliberately only re-crops
        // the backdrop already in hand — no capture, no blur — which is what
        // makes the glass track the desktop underneath in real time instead
        // of dragging a stale snapshot around behind it.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.publishCrop(for: window)
        }
        // Each Space can have its own wallpaper, and a display change moves or
        // rescales it — the two cases the slow timer would otherwise leave
        // showing the wrong picture for up to a minute.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.refresh(window: window, force: true)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.refresh(window: window, force: true)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
        for observer in [occlusionObserver, moveObserver, screenObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        occlusionObserver = nil
        moveObserver = nil
        spaceObserver = nil
        screenObserver = nil
        activeWindow = nil
    }

    /// Forces a capture outside the normal cadence. Used when a drag ends:
    /// the crop keeps the *position* honest during the gesture, but the pixels
    /// themselves are still up to one refresh interval old, so anything that
    /// has changed on screen at the new location would otherwise take until
    /// the next tick to show up.
    @MainActor
    func refreshNow() {
        guard let activeWindow else { return }
        refresh(window: activeWindow, force: true)
    }

    private func scheduleTimer(window: NSWindow) {
        // Idempotent: always safe to call, even to replace a timer that's
        // mid-fire (see the reschedule-on-interval-change below) — without
        // this, that path would leave the old timer running alongside the
        // new one instead of replacing it, ticking twice as often as
        // intended.
        timer?.invalidate()
        let interval = Self.refreshInterval(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.refresh(window: window)
            // Low Power Mode can toggle mid-run; re-scheduling on every
            // tick (cheap — one invalidate + one new Timer) keeps the
            // interval honest instead of only picking it up on next launch.
            let currentInterval = Self.refreshInterval(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
            if currentInterval != interval {
                self.scheduleTimer(window: window)
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-crops from whatever full-screen backdrop is already cached. Cheap
    /// enough to call on every drag event.
    /// Re-crops the cached full-display backdrop for the window's current
    /// position. Called on every frame of a drag (see
    /// `OverlayWindow.onDragStep`) as well as on `didMoveNotification`, so it
    /// has to stay cheap: one `CGImage.cropping`, which references the
    /// existing pixels rather than copying them.
    @MainActor
    func publishCrop(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main, let backdrop = fullBackdrop else { return }
        func crop(_ full: CGImage) -> CGImage? {
            // Pixel scale comes from the image itself: the dimmed backdrop is
            // kept at a fraction of screen resolution.
            guard let rect = Self.cropRect(
                windowFrame: window.frame,
                screenFrame: screen.frame,
                pixelScale: CGFloat(full.width) / screen.frame.width,
                imageSize: CGSize(width: full.width, height: full.height)
            ) else { return nil }
            return full.cropping(to: rect)
        }
        guard let vivid = crop(backdrop.vivid) else { return }
        image = vivid
        dimmedImage = crop(backdrop.dimmed)
    }

    private func refresh(window: NSWindow, force: Bool = false) {
        let blurRadius = activeBlurRadius
        let dimmedBlurRadius = activeDimmedBlurRadius
        // The capture is wallpaper-only, so it's valid even while app windows
        // cover the widget — take the first one regardless, or the widget
        // shows the fallback look for a beat each time it's first uncovered.
        guard fullBackdrop == nil || Self.shouldCapture(occlusionState: window.occlusionState) else { return }
        guard let screen = window.screen ?? NSScreen.main,
              let displayID = Self.displayID(of: screen) else { return }

        // Captured at 1 pixel per point, not the display's native density: the
        // result is blurred by at least 2.5pt and then heavily scaled into the
        // widget, so the extra pixels are invisible — but they quadrupled the
        // capture's memory (22MB -> 5.5MB per image on a Retina display) and
        // every blur's work.
        let pixelScale: CGFloat = 1
        captureTask?.cancel()
        captureTask = Task { [weak self, weak window] in
            let backdrop = await SharedBackdrop.shared.backdrop(
                displayID: displayID,
                blurRadius: blurRadius,
                dimmedBlurRadius: dimmedBlurRadius,
                pixelScale: pixelScale,
                force: force
            )
            guard !Task.isCancelled, let backdrop, let self, let window else { return }
            await MainActor.run {
                self.fullBackdrop = backdrop
                self.publishCrop(for: window)
            }
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

struct BackdropPair {
    let vivid: CGImage
    let dimmed: CGImage
}

/// One blurred full-display backdrop per display, shared by every widget on
/// it. Without this each widget would capture and blur the whole screen on
/// its own timer — the same work again for every world clock widget.
/// An `actor`, deliberately not a `@MainActor` type: the capture and the
/// full-screen `CIGaussianBlur` are the most expensive work in the app and
/// must not run on the main thread, or every refresh would hitch the UI.
private actor SharedBackdrop {
    static let shared = SharedBackdrop()

    private struct Entry {
        let pair: BackdropPair
        let blurRadius: CGFloat
        let dimmedBlurRadius: CGFloat
        let captured: Date
    }

    /// The dimmed backdrop is blurred so hard that full resolution buys
    /// nothing; working at a quarter of it makes that second blur cheap.
    private static let dimmedDownsample: CGFloat = 0.25

    private var entries: [CGDirectDisplayID: Entry] = [:]
    /// Intermediates aren't reused between captures a minute apart; keeping
    /// them cached only pinned tens of MB of blur buffers between refreshes.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Returns the display's blurred backdrop, re-capturing only if what's
    /// cached has aged past the refresh interval. Two widgets on one screen
    /// therefore cost one capture between them rather than one each — and
    /// because this is an actor, a second caller arriving mid-capture waits
    /// for that result instead of kicking off its own.
    func backdrop(displayID: CGDirectDisplayID, blurRadius: CGFloat, dimmedBlurRadius: CGFloat, pixelScale: CGFloat, force: Bool = false) async -> BackdropPair? {
        let interval = DesktopBackdropCapture.refreshInterval(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        if !force,
           let entry = entries[displayID],
           entry.blurRadius == blurRadius,
           entry.dimmedBlurRadius == dimmedBlurRadius,
           Date().timeIntervalSince(entry.captured) < interval {
            return entry.pair
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return entries[displayID]?.pair
            }
            // Wallpaper only — the same thing native widgets sample. Excluding
            // just our own windows (the old filter) still captured every app
            // window on screen, so the glass showed a blurred Safari/Preview
            // and kept showing it after that window was minimized, until the
            // next refresh happened to land while the widget was uncovered.
            let wallpaperWindows = content.windows.filter { DesktopBackdropCapture.isWallpaperLayer($0.windowLayer) }
            guard !wallpaperWindows.isEmpty else { return entries[displayID]?.pair }
            let filter = SCContentFilter(display: display, including: wallpaperWindows)

            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * pixelScale)
            config.height = Int(CGFloat(display.height) * pixelScale)
            config.showsCursor = false
            config.scalesToFit = false

            let raw = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let source = CIImage(cgImage: raw)
            let small = source.transformed(by: CGAffineTransform(scaleX: Self.dimmedDownsample, y: Self.dimmedDownsample))
            // Gaussians compose in quadrature, so this lands where blurring the
            // vivid backdrop by `dimmedBlurRadius` again would.
            let dimmedRadius = (blurRadius * blurRadius + dimmedBlurRadius * dimmedBlurRadius).squareRoot()
            guard let blurred = blur(source, radius: blurRadius * pixelScale),
                  let output = ciContext.createCGImage(blurred, from: source.extent),
                  let dimmedBlurred = blur(small, radius: dimmedRadius * pixelScale * Self.dimmedDownsample),
                  let dimmedOutput = ciContext.createCGImage(dimmedBlurred, from: small.extent) else {
                return entries[displayID]?.pair
            }
            let pair = BackdropPair(vivid: output, dimmed: dimmedOutput)
            entries[displayID] = Entry(pair: pair, blurRadius: blurRadius, dimmedBlurRadius: dimmedBlurRadius, captured: Date())
            return pair
        } catch {
            // Denied Screen Recording permission or a transient capture
            // failure — the last good backdrop (or none) stays in place and
            // `WidgetGlassBackground` falls back gracefully.
            return entries[displayID]?.pair
        }
    }

    private func blur(_ image: CIImage, radius: CGFloat) -> CIImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // `clampedToExtent()` matters more than it looks: without it the blur
        // samples transparent black from beyond the image bounds, so the
        // result's alpha falls off towards every edge (measured at ~52% in the
        // outer 10px vs ~99% in the middle). On screen that turned the widget's
        // whole rim semi-transparent, letting the sharp unblurred desktop leak
        // through exactly where the frosted edge should be.
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // Clamping makes the blur output infinite in extent — crop back to the
        // source rect so it lines up with the display's bounds.
        return output.cropped(to: image.extent)
    }
}
