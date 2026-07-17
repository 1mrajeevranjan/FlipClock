import SwiftUI
import AppKit

/// Frosted-glass container matching the default macOS desktop widget look
/// (Calendar/Weather widgets in Notification Center): a behind-window
/// vibrant blur clipped to a large rounded rect, with a faint inner
/// highlight stroke, a size-proportional soft shadow, and the window's own
/// drop shadow doing the rest.
struct WidgetGlassBackground: View {
    /// The widget's `overlaySize.scale` (0.325/0.65/1.3/1.95) — drives both
    /// corner radius and shadow so they scale with widget size instead of
    /// staying fixed constants, per Apple's Widget HIG guidance that a
    /// widget's corner radius should track its container rather than be a
    /// flat value.
    var scale: CGFloat = 1
    /// Full-screen mode wants completely transparent glass — no blur, no
    /// tint, no stroke, no shadow, just the raw desktop showing through with
    /// the clock floating on top of it — rather than a widget-style frosted
    /// panel that would visibly gray out the whole screen.
    var fullyClear: Bool = false

    /// `34 * scale`, clamped to `14...40`. The default `.full` size
    /// (`scale = 0.65`) now renders at `22pt` — smaller than the old flat
    /// `34pt` constant, a deliberate change to make radius track widget
    /// size rather than stay fixed; `scale = 1` is just the formula's
    /// anchor point (`OverlaySize` never actually reaches it), not the
    /// default.
    static func cornerRadius(scale: CGFloat) -> CGFloat {
        (34 * scale).clamped(to: 14...40)
    }

    private var cornerRadius: CGFloat {
        fullyClear ? 0 : Self.cornerRadius(scale: scale)
    }

    var body: some View {
        if fullyClear {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .background(
                    VisualEffectBlur()
                        .opacity(0.22)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(
                    color: .black.opacity(0.18),
                    radius: (12 * scale).clamped(to: 6...20),
                    x: 0,
                    y: (4 * scale).clamped(to: 2...8)
                )
        }
    }
}

/// Bridges `NSVisualEffectView` with `.behindWindow` blending so the blur
/// samples the desktop wallpaper/icons beneath the overlay window, not just
/// this view's own SwiftUI content — SwiftUI's `Material` types only blend
/// with what's drawn inside the same view hierarchy, which isn't enough
/// here since the window itself is transparent over the desktop.
///
/// `.underWindowBackground` is the material that actually tints with the
/// wallpaper hue behind it (the "colorful" glass Calendar/Weather widgets
/// show) — `.hudWindow` reads as flat neutral gray regardless of what's
/// behind the window, which is why the first pass looked wrong.
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Comparable {
    /// Constrains `self` to `range`, used to keep size-scaled widget metrics
    /// (corner radius, padding, shadow) within sane bounds at the smallest
    /// and largest `OverlaySize` scales.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
