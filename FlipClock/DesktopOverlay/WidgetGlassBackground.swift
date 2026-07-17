import SwiftUI
import AppKit

/// Frosted-glass container matching the default macOS desktop widget look
/// (Calendar/Weather widgets in Notification Center): a behind-window
/// vibrant blur clipped to a large rounded rect, with a faint inner
/// highlight stroke and the window's own drop shadow doing the rest.
struct WidgetGlassBackground: View {
    static let cornerRadius: CGFloat = 34

    /// 0 for the full-screen mode, where the glass is a square, edge-to-edge
    /// layer rather than a floating rounded widget.
    var cornerRadius: CGFloat = Self.cornerRadius
    /// Full-screen mode wants completely transparent glass — no blur, no
    /// tint, no stroke, just the raw desktop showing through with the
    /// clock floating on top of it — rather than a widget-style frosted
    /// panel that would visibly gray out the whole screen.
    var fullyClear: Bool = false

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
