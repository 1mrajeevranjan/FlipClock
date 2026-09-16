import AppKit
import CoreImage
import ScreenCaptureKit

/// Software equivalent of `NSVisualEffectView.behindWindow` blending, but
/// with a real, tunable Gaussian blur radius — `NSVisualEffectView`'s own
/// blur radius is fixed by the system material and isn't a public API, so
/// no amount of `.opacity()` on it can push the diffusion past what that
/// fixed radius produces. This captures a still image of whatever sits
/// behind the overlay window, blurs it heavily with Core Image, and
/// republishes it on a timer — strong enough to match Notification
/// Center's own widget diffusion.
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

    private let ciContext = CIContext()
    private var timer: Timer?
    private var occlusionObserver: NSObjectProtocol?
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
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
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

    private func refresh(window: NSWindow, blurRadius: CGFloat) {
        guard Self.shouldCapture(occlusionState: window.occlusionState) else { return }
        let windowID = CGWindowID(window.windowNumber)
        let frame = window.frame
        guard let screen = window.screen ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        // ScreenCaptureKit's `sourceRect` is in the display's own top-left,
        // Y-down pixel space; `NSWindow.frame` is Cocoa screen space
        // (origin bottom-left, Y up) — flip against the screen's own frame,
        // not the primary screen's, so this is correct on secondary displays.
        let captureRect = CGRect(
            x: frame.minX - screen.frame.minX,
            y: screen.frame.height - (frame.maxY - screen.frame.minY),
            width: frame.width,
            height: frame.height
        )
        // Capture at the display's real pixel density. Requesting a
        // point-sized image on a Retina screen hands back a half-resolution
        // backdrop that then gets upscaled 2x to fill the widget — and that
        // upscale smooths away far more detail than the Gaussian does, which
        // is why shrinking the blur radius barely changed how diffuse the
        // panel looked. The radius is in pixels, so it scales with the image.
        let pixelScale = screen.backingScaleFactor

        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID.uint32Value }) else { return }
                // Only our own window is excluded. Excluding every window (to
                // capture strictly the desktop behind the overlay) reads better
                // in principle but fails outright here — SCK returns -3811
                // "Failed to start stream" for a filter that excludes
                // everything. The occlusion gate in `shouldCapture` already
                // skips the case this would have covered, since a widget that's
                // fully behind another window isn't being composited anyway.
                let ourWindow = content.windows.first { $0.windowID == windowID }
                let filter = SCContentFilter(display: display, excludingWindows: ourWindow.map { [$0] } ?? [])
                let config = SCStreamConfiguration()
                config.sourceRect = captureRect
                config.width = max(1, Int(captureRect.width * pixelScale))
                config.height = max(1, Int(captureRect.height * pixelScale))
                config.showsCursor = false
                config.scalesToFit = false

                let raw = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()

                let source = CIImage(cgImage: raw)
                guard let blurred = self.blur(source, radius: blurRadius * pixelScale),
                      let output = self.ciContext.createCGImage(blurred, from: source.extent) else { return }

                await MainActor.run { [weak self] in
                    self?.image = output
                }
            } catch {
                // Denied Screen Recording permission or a transient capture
                // failure — `image` just stays whatever it last was (or nil),
                // and `WidgetGlassBackground` falls back gracefully.
            }
        }
    }

    private func blur(_ image: CIImage, radius: CGFloat) -> CIImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // `clampedToExtent()` matters more than it looks: without it the blur
        // samples transparent black from beyond the image bounds, so the
        // result's alpha falls off towards every edge (measured at ~52% in the
        // outer 10px vs ~99% in the middle). On screen that turned the widget's
        // whole rim semi-transparent, letting the sharp unblurred desktop leak
        // through exactly where the frosted edge should be — the single biggest
        // reason this didn't read like a native widget's glass.
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // Clamping makes the blur output infinite in extent — crop back to the
        // source rect so it lines up with the widget's bounds.
        return output.cropped(to: image.extent)
    }
}
