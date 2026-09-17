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
/// adding the second clock widget doesn't double it.
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

    /// Last full-display blurred backdrop this widget received. Held here so
    /// `publishCrop` can crop synchronously on the main thread while dragging
    /// — going back to the shared store for it would make every drag event an
    /// `await`, and the glass would lag the window by a frame or more.
    private var fullBackdrop: CGImage?

    private var timer: Timer?
    private var occlusionObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
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

    /// Refresh cadence — stretched out under Low Power Mode as a second,
    /// smaller battery win on top of the occlusion gate above (which
    /// already eliminates the bulk of the waste). Pulled out as a pure
    /// function for the same testability reason.
    static func refreshInterval(isLowPowerModeEnabled: Bool) -> TimeInterval {
        isLowPowerModeEnabled ? 15.0 : 5.0
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

    func start(window: NSWindow, blurRadius: CGFloat) {
        stop()
        refresh(window: window, blurRadius: blurRadius)
        scheduleTimer(window: window, blurRadius: blurRadius)
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
            self.refresh(window: window, blurRadius: blurRadius)
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
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
        for observer in [occlusionObserver, moveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        occlusionObserver = nil
        moveObserver = nil
    }

    private func scheduleTimer(window: NSWindow, blurRadius: CGFloat) {
        // Idempotent: always safe to call, even to replace a timer that's
        // mid-fire (see the reschedule-on-interval-change below) — without
        // this, that path would leave the old timer running alongside the
        // new one instead of replacing it, ticking twice as often as
        // intended.
        timer?.invalidate()
        let interval = Self.refreshInterval(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.refresh(window: window, blurRadius: blurRadius)
            // Low Power Mode can toggle mid-run; re-scheduling on every
            // tick (cheap — one invalidate + one new Timer) keeps the
            // interval honest instead of only picking it up on next launch.
            let currentInterval = Self.refreshInterval(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
            if currentInterval != interval {
                self.scheduleTimer(window: window, blurRadius: blurRadius)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-crops from whatever full-screen backdrop is already cached. Cheap
    /// enough to call on every drag event.
    @MainActor
    private func publishCrop(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main, let backdrop = fullBackdrop else { return }
        guard let crop = Self.cropRect(
            windowFrame: window.frame,
            screenFrame: screen.frame,
            pixelScale: screen.backingScaleFactor,
            imageSize: CGSize(width: backdrop.width, height: backdrop.height)
        ), let cropped = backdrop.cropping(to: crop) else { return }
        image = cropped
    }

    private func refresh(window: NSWindow, blurRadius: CGFloat) {
        guard Self.shouldCapture(occlusionState: window.occlusionState) else { return }
        guard let screen = window.screen ?? NSScreen.main,
              let displayID = Self.displayID(of: screen) else { return }

        let pixelScale = screen.backingScaleFactor
        captureTask?.cancel()
        captureTask = Task { [weak self, weak window] in
            let backdrop = await SharedBackdrop.shared.backdrop(
                displayID: displayID,
                blurRadius: blurRadius,
                pixelScale: pixelScale
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

/// One blurred full-display backdrop per display, shared by every widget on
/// it. Without this each widget would capture and blur the whole screen on
/// its own timer — the same work twice for the clock and the second clock.
/// An `actor`, deliberately not a `@MainActor` type: the capture and the
/// full-screen `CIGaussianBlur` are the most expensive work in the app and
/// must not run on the main thread, or every refresh would hitch the UI.
private actor SharedBackdrop {
    static let shared = SharedBackdrop()

    private struct Entry {
        let image: CGImage
        let blurRadius: CGFloat
        let captured: Date
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private let ciContext = CIContext()

    /// Returns the display's blurred backdrop, re-capturing only if what's
    /// cached has aged past the refresh interval. Two widgets on one screen
    /// therefore cost one capture between them rather than one each — and
    /// because this is an actor, a second caller arriving mid-capture waits
    /// for that result instead of kicking off its own.
    func backdrop(displayID: CGDirectDisplayID, blurRadius: CGFloat, pixelScale: CGFloat) async -> CGImage? {
        let interval = DesktopBackdropCapture.refreshInterval(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        if let entry = entries[displayID],
           entry.blurRadius == blurRadius,
           Date().timeIntervalSince(entry.captured) < interval {
            return entry.image
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return entries[displayID]?.image
            }
            // Every window this app owns is excluded, not just the one being
            // drawn: capturing the whole display means a widget would
            // otherwise blur *itself* and its sibling into its own backdrop.
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ourWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
            let filter = SCContentFilter(display: display, excludingWindows: ourWindows)

            let config = SCStreamConfiguration()
            // Native pixel density: a point-sized request hands back a
            // half-resolution backdrop that then gets upscaled into the
            // widget, and that upscale smooths away more detail than the
            // Gaussian does.
            config.width = Int(CGFloat(display.width) * pixelScale)
            config.height = Int(CGFloat(display.height) * pixelScale)
            config.showsCursor = false
            config.scalesToFit = false

            let raw = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let source = CIImage(cgImage: raw)
            guard let blurred = blur(source, radius: blurRadius * pixelScale),
                  let output = ciContext.createCGImage(blurred, from: source.extent) else {
                return entries[displayID]?.image
            }
            entries[displayID] = Entry(image: output, blurRadius: blurRadius, captured: Date())
            return output
        } catch {
            // Denied Screen Recording permission or a transient capture
            // failure — the last good backdrop (or none) stays in place and
            // `WidgetGlassBackground` falls back gracefully.
            return entries[displayID]?.image
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
