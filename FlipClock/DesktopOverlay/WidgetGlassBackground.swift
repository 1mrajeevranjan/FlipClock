import SwiftUI
import AppKit

/// Frosted-glass container matching the default macOS desktop widget look
/// (Calendar/Weather widgets in Notification Center): a behind-window
/// vibrant blur, masked to a large rounded rect on its own layer (not a
/// SwiftUI overlay clip — see `VisualEffectBlur`), plus a size-proportional
/// soft shadow. Deliberately has no stroke/highlight overlay — Apple's own
/// widgets don't draw one, and adding one is what previously left a faint
/// ring at the corners.
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
                    // The corner rounding lives on the NSVisualEffectView's
                    // own CALayer (see `VisualEffectBlur`), not a SwiftUI
                    // `.clipShape` on top of it — clipping a live
                    // behind-window blur from the outside leaves a faint
                    // antialiasing fringe right at the curve, which is
                    // exactly the hairline this replaces. Masking the
                    // layer that's actually doing the sampling gives the
                    // same clean edge macOS's own widgets have.
                    //
                    // Stacking a SwiftUI `.ultraThinMaterial` on top of this
                    // (tried in an earlier pass) was a mistake: Material
                    // renders its own light-appearance fill underneath the
                    // blur, which is what washed the whole panel out toward
                    // opaque white, killed the digit cards' contrast, and
                    // even reintroduced a corner seam (its clip doesn't
                    // line up with the layer-masked blur beneath it).
                    // `.underWindowBackground` alone, at full strength (no
                    // `.opacity()` dampening at all — the previous 0.94/0.68
                    // values were both artificially thinning the one lever
                    // that actually matters here), is the correct approach.
                    VisualEffectBlur(cornerRadius: cornerRadius)
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
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
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
