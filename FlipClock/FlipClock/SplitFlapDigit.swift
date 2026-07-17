import SwiftUI
import AppKit

/// One flap position: a static top half, a static bottom half, and the
/// animating flap layered on top. Works for a single digit ("7") or a
/// short label ("AM") — same card, same flip mechanism either way. Top
/// half updates the instant the value changes (in the real mechanism the
/// housing behind the flipping leaf already shows the upcoming value);
/// bottom half only updates once the flap finishes landing, so the new
/// value never "peeks" early.
struct SplitFlapDigit: View {
    let value: String
    let cardSize: CGSize
    var isDark: Bool = true
    var compact: Bool = false
    var textColor: NSColor? = nil
    /// Whether this card is fused edge-to-edge with a neighbor on that
    /// side — a fused edge gets no housing corner rounding (it reads as
    /// one continuous drum with its neighbor, like "1" and "0" inside a
    /// single "10" module) and no spool cap (the axle only pokes out at
    /// the true outer ends of a fused run, not at every internal digit
    /// boundary).
    var fusedLeading: Bool = false
    var fusedTrailing: Bool = false
    /// "Liquid glass" card style: card faces render with a transparent
    /// background (see `DigitFaceRenderer`) instead of a solid leaf fill,
    /// so the digit reads as drawn on frosted glass. Also governs the
    /// animating flap's tint (translucent instead of opaque leaf color)
    /// and shadow (off — a drop shadow doesn't belong on glass) so the
    /// flip matches the resting card instead of visibly changing style
    /// mid-animation.
    var glassCard: Bool = false
    /// Whether this card draws its own behind-window blur panel. Only
    /// meaningful when `glassCard` is true. The desktop overlay wants
    /// this (each card samples its own patch of desktop); the popover
    /// doesn't (it already sits on `VibrantHostingController`'s own
    /// blur — a second independent `NSVisualEffectView` per card just
    /// grays everything out instead of compositing).
    var showOwnGlassPanel: Bool = true

    @State private var topValue: String
    @State private var bottomValue: String
    /// Bumped every time a flip lands, to force `CardGlassBackground` to
    /// re-kick its `NSVisualEffectView` — see the doc comment there for
    /// why that's necessary.
    @State private var glassRefreshTick = 0

    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil, fusedLeading: Bool = false, fusedTrailing: Bool = false, glassCard: Bool = false, showOwnGlassPanel: Bool = true) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        self.fusedLeading = fusedLeading
        self.fusedTrailing = fusedTrailing
        self.glassCard = glassCard
        self.showOwnGlassPanel = showOwnGlassPanel
        _topValue = State(initialValue: value)
        _bottomValue = State(initialValue: value)
    }

    private var cornerRadius: CGFloat { compact ? 2 : 6 }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: fusedLeading ? 0 : cornerRadius,
            bottomLeadingRadius: fusedLeading ? 0 : cornerRadius,
            bottomTrailingRadius: fusedTrailing ? 0 : cornerRadius,
            topTrailingRadius: fusedTrailing ? 0 : cornerRadius
        )
    }

    var body: some View {
        ZStack {
            if glassCard && showOwnGlassPanel {
                CardGlassBackground(refreshTrigger: glassRefreshTick).clipShape(cardShape)
            }

            VStack(spacing: 0) {
                HalfCard(image: DigitFaceRenderer.halfFace(for: topValue, cardSize: cardSize, top: true, isDark: isDark, textColor: textColor, transparentBackground: glassCard))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
                HalfCard(image: DigitFaceRenderer.halfFace(for: bottomValue, cardSize: cardSize, top: false, isDark: isDark, textColor: textColor, transparentBackground: glassCard))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
            }
            .clipShape(cardShape)

            HingeLine(width: cardSize.width, isDark: isDark, compact: compact)

            // The animating leaf always renders opaque, even in glass
            // mode — it needs to fully mask the static half underneath
            // while it's mid-rotation, or the old digit bleeds through the
            // new one and reads as a double-exposed "ghost" during the
            // flip (only the idle resting card should be see-through).
            // `glassCard` still tints that opaque fill to a translucent
            // tone so the card doesn't visibly flash to a different color
            // for the flip's duration.
            FlipCardLayer(value: value, cardSize: cardSize, isDark: isDark, glassCard: glassCard) {
                bottomValue = value
                glassRefreshTick += 1
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(cardShape)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .onChange(of: value) { _, newValue in
            topValue = newValue
        }
    }
}

/// The frosted-glass panel behind a single glass-style card — same
/// behind-window blur technique as `WidgetGlassBackground`, sized to one
/// card instead of the whole overlay.
private struct CardGlassBackground: View {
    var refreshTrigger: Int = 0

    var body: some View {
        VisualEffectCardBlur(refreshTrigger: refreshTrigger)
    }
}

/// `NSVisualEffectView.behindWindow` blending stops re-sampling the
/// desktop and freezes on its last-drawn pixels once fully covered for a
/// while (here, by the opaque animating flap during a flip) — measured
/// directly off a screen recording: the same card position read as live,
/// varying color before a flip and was frozen at one flat gray for many
/// seconds after, never recovering. Toggling `.state` forces the
/// compositor to treat it as freshly active and resume live sampling.
private struct VisualEffectCardBlur: NSViewRepresentable {
    var refreshTrigger: Int

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .inactive
        nsView.state = .active
    }
}

/// `NSVisualEffectView` returns `false` from `mouseDownCanMoveWindow` by
/// default, which silently defeats the desktop overlay window's
/// `isMovableByWindowBackground = true` everywhere a card's own glass panel
/// covers — since `showOwnGlassPanel` tiles one of these per digit across
/// nearly the whole widget, that's most of its surface. Overriding it here
/// is what actually lets the widget be dragged by its background.
private final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct HalfCard: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
    }
}

/// The seam between the two half-cards — a single flat rule, no
/// shadow/highlight bands (those read as a smudge, not a fold).
private struct HingeLine: View {
    let width: CGFloat
    let isDark: Bool
    let compact: Bool

    private var coreHeight: CGFloat { compact ? 1.5 : 3.5 }

    var body: some View {
        Rectangle()
            .fill(FlapColors.leafHinge(isDark: isDark))
            .frame(width: width, height: coreHeight)
    }
}
