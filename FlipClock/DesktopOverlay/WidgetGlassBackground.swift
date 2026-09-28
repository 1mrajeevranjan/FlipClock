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
    /// A pre-blurred snapshot of whatever sits behind the window, supplied
    /// by `DesktopBackdropCapture` — `nil` until the first capture lands
    /// (or forever, if Screen Recording access was denied), in which case
    /// this falls back to the live `NSVisualEffectView` blur below.
    var backdropImage: CGImage? = nil
    /// The same backdrop pre-blurred for the dimmed look (see
    /// `DesktopBackdropCapture.dimmedImage`).
    var dimmedBackdropImage: CGImage? = nil
    /// Which of macOS's three widget looks to render (see `GlassTone`).
    /// Monochrome is a deliberate user choice and drains the glass all the
    /// way to greyscale.
    ///
    /// Dimmed is deliberately *not* full greyscale. Measuring a real widget
    /// while the system had it dimmed showed its glass still carrying some
    /// colour (saturation ~0.13-0.25 over a ~0.3 wallpaper) but far more
    /// diffused than the vivid state — nearly a flat average of what's behind
    /// it. So dimming pulls the vibrancy back, deepens the scrim a little, and
    /// adds a second blur on top of the captured one.
    var tone: GlassTone = .vivid

    private var monochrome: Bool { tone == .monochrome }
    private var dimmed: Bool { tone == .dimmed }

    /// Extra diffusion the dimmed backdrop gets on top of the vivid one's
    /// blur. Baked into a second capture image (not a live SwiftUI `.blur`,
    /// which was too heavy to animate smoothly across the panel).
    static func dimmedBlur(scale: CGFloat) -> CGFloat {
        (18 * scale).clamped(to: 8...28)
    }

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

    /// macOS HIG: when the user turns on "Reduce transparency"
    /// (System Settings > Accessibility > Display), translucent materials
    /// must be swapped for an opaque equivalent rather than staying
    /// see-through — a live desktop-sampling blur is the single most
    /// literal case that setting exists for.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.colorSchemeContrast) private var contrast

    private var isDark: Bool { colorScheme == .dark }

    /// HIG: with Increase Contrast on, native widgets trade their soft glass
    /// edge for a solid outline so the panel separates from any wallpaper.
    private var increasedContrastEdge: Color? {
        contrast == .increased ? Color(nsColor: .separatorColor) : nil
    }

    @ViewBuilder
    private func rim(_ shape: RoundedRectangle) -> some View {
        if let edge = increasedContrastEdge {
            shape.strokeBorder(edge, lineWidth: 1)
        } else {
            // The glossy rim macOS's own widgets have: a bright specular arc
            // along the top edge fading to almost nothing by the sides/bottom
            // — light catching curved glass from above, not a stroke drawn
            // all the way around (which is what previously read as an
            // artificial "ring").
            shape.strokeBorder(
                AngularGradient(
                    colors: [.white.opacity(0.05), .white.opacity(0.55), .white.opacity(0.05)],
                    center: .center,
                    startAngle: .degrees(200),
                    endAngle: .degrees(340)
                ),
                lineWidth: 1
            )
            .blendMode(.plusLighter)
        }
    }

    /// Measured off real widget glass rather than guessed: sampling a
    /// Notification Center widget against the wallpaper band running right
    /// beside it, the widget comes out *darker* than the desktop behind it
    /// (mean luminance 110 against 124), not lighter. A white scrim — the
    /// intuitive choice for "frosted" — pushed the panel the wrong way, to
    /// 142. macOS darkens widget glass so content stays legible over a bright
    /// photo, and that slight deepening is a real part of the look.
    static func scrim(isDark: Bool, dimmed: Bool) -> Color {
        let base = isDark ? 0.20 : 0.05
        return Color.black.opacity(dimmed ? base + 0.08 : base)
    }

    /// See the `.saturation` call site — real widget glass runs its backdrop
    /// hotter than the desktop behind it, and matching that is what separates
    /// "vibrant glass" from "a blurry screenshot of the wallpaper".
    static let vibrancy: Double = 1.35

    /// Dimmed still keeps the backdrop in colour (see `dimmed`); it just stops
    /// boosting it, landing near the wallpaper's own saturation.
    static let dimmedVibrancy: Double = 0.75

    /// Passing the backdrop through at saturation 1 is what kept this reading
    /// as a flat grey-brown panel next to the real thing.
    /// `NSVisualEffectView`'s materials don't just blur, they push saturation
    /// up — measured against the wallpaper band beside a Notification Center
    /// widget, the wallpaper sits at ~0.31 saturation and the widget's glass at
    /// ~0.42, a ~1.35x boost. That colour lift is most of what reads as
    /// "vibrancy" rather than "a blurry screenshot".
    static func saturation(monochrome: Bool, dimmed: Bool) -> Double {
        if monochrome { return 0 }
        return dimmed ? dimmedVibrancy : vibrancy
    }

    /// `.frame` from the measured size, not the proposal — see the
    /// `GeometryReader` note in `glass`.
    private func backdropLayer(_ image: CGImage, size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    var body: some View {
        // Every path gets the drag handle behind it, not just the
        // `VisualEffectBlur` fallback. That view's `mouseDownCanMoveWindow`
        // override used to be the only thing making the widget draggable, so
        // dragging silently stopped working the moment the ScreenCaptureKit
        // capture started succeeding reliably and the `Image` path took over —
        // a plain SwiftUI `Image` puts no AppKit view under the cursor, and
        // `isMovableByWindowBackground` has nothing to ask.
        glass.background(WindowDragHandle())
    }

    @ViewBuilder
    private var glass: some View {
        if fullyClear {
            Color.clear
        } else if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(increasedContrastEdge.map { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder($0, lineWidth: 1) })
                .shadow(
                    color: .black.opacity(0.28),
                    radius: (16 * scale).clamped(to: 8...26),
                    x: 0,
                    y: (6 * scale).clamped(to: 3...10)
                )
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(.clear)
                .background(
                    GeometryReader { proxy in
                        // `Image().resizable().aspectRatio(.fill)` sizes
                        // itself from the *proposed* size flowing down
                        // through `.background()` — through this
                        // particular chain (shape -> background ->
                        // conditional content) that proposal wasn't
                        // actually bounded, so the image rendered at its
                        // full captured-bitmap resolution instead of the
                        // widget's real size: only a sliver of true curve
                        // showed near the corner before a huge image
                        // "straightened out" past it. An explicit
                        // `.frame(width:height:)` from `GeometryReader`'s
                        // own measured size removes the ambiguity — the
                        // image is now forced to exactly the container's
                        // pixel bounds before it's ever clipped.
                        Group {
                            if let backdropImage {
                                // A real, strongly Gaussian-blurred bitmap
                                // of whatever's behind the window (see
                                // `DesktopBackdropCapture`) — this is what
                                // actually reaches Notification Center
                                // widget levels of diffusion, since
                                // `NSVisualEffectView`'s own blur radius is
                                // fixed and isn't a public API.
                                ZStack {
                                    backdropLayer(backdropImage, size: proxy.size)
                                        .saturation(Self.saturation(monochrome: monochrome, dimmed: false))
                                    // The dimmed look is its own pre-blurred
                                    // image faded in on top, so switching
                                    // looks animates nothing but opacity and a
                                    // colour matrix — cheap enough to run at
                                    // full frame rate from the first frame.
                                    if let dimmedBackdropImage {
                                        backdropLayer(dimmedBackdropImage, size: proxy.size)
                                            .saturation(Self.saturation(monochrome: false, dimmed: true))
                                            .opacity(dimmed ? 1 : 0)
                                    }
                                }
                                // The blurred wallpaper alone reads as dark
                                // smoked glass, not frosted glass. macOS's
                                // own widgets lay a translucent scrim over
                                // the blur — that's what gives them their
                                // milky lift and keeps content legible over
                                // a dark wallpaper. A flat white/black pair
                                // (rather than a SwiftUI `Material`, which
                                // does its own sampling and washed the panel
                                // out entirely when tried before) keeps the
                                // strength tunable and predictable.
                                .overlay(Self.scrim(isDark: isDark, dimmed: dimmed))
                            } else {
                                // The corner rounding lives on the
                                // NSVisualEffectView's own CALayer (see
                                // `VisualEffectBlur`), not a SwiftUI
                                // `.clipShape` on top of it — clipping a
                                // live behind-window blur from the outside
                                // leaves a faint antialiasing fringe right
                                // at the curve. Masking the layer that's
                                // actually doing the sampling gives a
                                // clean edge instead. This path only
                                // renders before the first capture lands,
                                // or permanently if Screen Recording
                                // access was denied.
                                VisualEffectBlur(cornerRadius: cornerRadius)
                                    .saturation(Self.saturation(monochrome: monochrome, dimmed: dimmed))
                            }
                        }
                    }
                    .clipShape(shape)
                )
                .overlay(rim(shape).allowsHitTesting(false))
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

/// A plain AppKit view whose only job is to answer `true` to
/// `mouseDownCanMoveWindow`, so `OverlayWindow.isMovableByWindowBackground`
/// has something to act on wherever the widget's SwiftUI content doesn't
/// claim the click itself. Sits behind the glass, so anything interactive
/// added to the widget later still hit-tests first and wins.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
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
