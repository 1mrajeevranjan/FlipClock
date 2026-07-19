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
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(.clear)
                .background(
                    // Pushed well past the old 0.22 — at this opacity the
                    // behind-window blur itself (not just a tint over sharp
                    // pixels) dominates what reads through, which is what
                    // makes the desktop underneath look genuinely diffused
                    // rather than merely darkened.
                    VisualEffectBlur()
                        .opacity(0.68)
                        .clipShape(shape)
                )
                .overlay(
                    // A directional highlight (bright upper-left, fading to
                    // near-nothing lower-right) instead of a flat stroke —
                    // reads as a light source catching the rim of a curved
                    // glass edge rather than a drawn outline.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
                )
                .overlay(
                    // Soft specular wash across the top third — the "light
                    // leaking through" glass look — additive so it brightens
                    // rather than flattening whatever's blurred beneath it.
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.42)
                    )
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                )
                .shadow(
                    color: .black.opacity(0.28),
                    radius: (16 * scale).clamped(to: 8...26),
                    x: 0,
                    y: (6 * scale).clamped(to: 3...10)
                )
                .shadow(
                    color: .black.opacity(0.14),
                    radius: (4 * scale).clamped(to: 2...7),
                    x: 0,
                    y: (1.5 * scale).clamped(to: 1...3)
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
        let view = DraggableVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// `NSVisualEffectView` returns `false` from `mouseDownCanMoveWindow` by
/// default, which silently defeats the overlay window's
/// `isMovableByWindowBackground = true` everywhere this blur covers —
/// practically the whole widget surface. Overriding it here is what
/// actually lets the widget be dragged by its background.
private final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

extension Comparable {
    /// Constrains `self` to `range`, used to keep size-scaled widget metrics
    /// (corner radius, padding, shadow) within sane bounds at the smallest
    /// and largest `OverlaySize` scales.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
