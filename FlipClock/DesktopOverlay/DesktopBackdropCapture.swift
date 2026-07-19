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

    func start(window: NSWindow, blurRadius: CGFloat) {
        stop()
        _ = CGRequestScreenCaptureAccess()
        refresh(window: window, blurRadius: blurRadius)
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.refresh(window: window, blurRadius: blurRadius)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh(window: NSWindow, blurRadius: CGFloat) {
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
