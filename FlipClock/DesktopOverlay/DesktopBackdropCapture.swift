import AppKit
import CoreImage

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
final class DesktopBackdropCapture: ObservableObject {
    @Published private(set) var image: CGImage?

    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "com.rajeevranjan.flipclock.backdrop-capture", qos: .utility)
    private var timer: Timer?
    private var occlusionObserver: NSObjectProtocol?

    /// Whether a capture is worth doing right now — pulled out as a pure
    /// function (no window/system calls) so it's directly unit-testable.
    /// `CGWindowListCreateImage` + `CIGaussianBlur` was, by a wide margin,
    /// the single biggest CPU/GPU/battery cost anywhere in the app (already
    /// throttled once, from 1s to 5s, per the comment below) — but even at
    /// 5s it ran unconditionally forever, including the common case where
    /// the overlay sits fully covered by another app's window (it's
    /// deliberately layered below normal windows — see
    /// `OverlayWindowController`) and literally nobody can see the result.
    /// `occlusionState.contains(.visible)` is exactly the signal AppKit
    /// already tracks for "is any pixel of this window actually being
    /// composited to the screen" — false whenever it's fully covered,
    /// minimized, on another Space, or the display is asleep/locked.
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
        _ = CGRequestScreenCaptureAccess()
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
        // `CGWindowListCreateImage` expects the CoreGraphics global display
        // space (origin top-left, Y down); `NSWindow.frame` is in Cocoa
        // screen space (origin bottom-left, Y up) — flip against the
        // primary screen's height to convert.
        let screenHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        let cgRect = CGRect(
            x: frame.minX,
            y: screenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )

        queue.async { [weak self] in
            guard let self,
                  let raw = CGWindowListCreateImage(cgRect, .optionOnScreenBelowWindow, windowID, .bestResolution) else {
                return
            }
            let source = CIImage(cgImage: raw)
            guard let blurred = self.blur(source, radius: blurRadius),
                  let output = self.ciContext.createCGImage(blurred, from: source.extent) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.image = output
            }
        }
    }

    private func blur(_ image: CIImage, radius: CGFloat) -> CIImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // Gaussian blur expands the image's extent outward by roughly the
        // radius — cropping back to the source rect avoids a shrunken/
        // semi-transparent fringe at the edges.
        return output.cropped(to: image.extent)
    }
}
