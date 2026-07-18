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
    /// HIG-style accent tint. When set, this wins over `textColor` for the
    /// digit ink (a global "themed" mode beats the one-off Sunday-red
    /// weekday case), and also drives the hinge line and frosted-card fill
    /// via the tint-aware `FlapColors` overloads.
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
    /// Whether this card is fused edge-to-edge with a neighbor on that
    /// side — a fused edge gets no housing corner rounding (it reads as
    /// one continuous drum with its neighbor, like "1" and "0" inside a
    /// single "10" module) and no spool cap (the axle only pokes out at
    /// the true outer ends of a fused run, not at every internal digit
    /// boundary).
    var fusedLeading: Bool = false
    var fusedTrailing: Bool = false
    /// "Frosted glass" card style: the card face is a single opaque frosted
    /// tone (`FlapColors.frostedCard`), used identically by the resting
    /// halves and the animating flap. Because both share that exact opaque
    /// tone, a flip never changes the card's look — the flap has to stay
    /// opaque to mask the old digit mid-rotation, but there's no
    /// transparent/live-blur resting state for it to visibly flash away
    /// from. The floating widget panel behind the cards stays real glass.
    var glassCard: Bool = false
    /// Retained for source compatibility with existing call sites; no
    /// longer affects rendering. Frosted cards are opaque, so there's no
    /// per-card behind-window blur to draw (and thus none of the freeze/
    /// flicker behavior an `NSVisualEffectView` per card used to cause).
    var showOwnGlassPanel: Bool = true

    @State private var topValue: String
    @State private var bottomValue: String

    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil, fusedLeading: Bool = false, fusedTrailing: Bool = false, glassCard: Bool = false, showOwnGlassPanel: Bool = true, tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        self.fusedLeading = fusedLeading
        self.fusedTrailing = fusedTrailing
        self.glassCard = glassCard
        self.showOwnGlassPanel = showOwnGlassPanel
        self.tintColor = tintColor
        self.fontName = fontName
        self.isMonospacedSystemFont = isMonospacedSystemFont
        _topValue = State(initialValue: value)
        _bottomValue = State(initialValue: value)
    }

    private var cornerRadius: CGFloat { compact ? 2 : 6 }

    /// Tint wins over the `textColor` override (e.g. Sunday-red) when
    /// present — see the doc comment on `tintColor` above.
    private var effectiveTextColor: NSColor? {
        tintColor.map(NSColor.init) ?? textColor
    }

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
            if glassCard {
                // Opaque frosted base, drawn by a real drag-enabled NSView
                // (see `DraggableColorView`) so the desktop overlay stays
                // draggable by its background over the cards. The static
                // halves render their digit on a transparent background and
                // composite on top of this, so the resting card is exactly
                // "frosted tone + digit" — identical to what the flap draws.
                DraggableColorView(color: FlapColors.frostedCard(isDark: isDark, tint: tintColor)).clipShape(cardShape)
            }

            VStack(spacing: 0) {
                HalfCard(image: DigitFaceRenderer.halfFace(for: topValue, cardSize: cardSize, top: true, isDark: isDark, textColor: effectiveTextColor, transparentBackground: glassCard, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
                HalfCard(image: DigitFaceRenderer.halfFace(for: bottomValue, cardSize: cardSize, top: false, isDark: isDark, textColor: effectiveTextColor, transparentBackground: glassCard, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
            }
            .clipShape(cardShape)

            HingeLine(width: cardSize.width, isDark: isDark, compact: compact, tint: tintColor)

            // The animating leaf always renders opaque — it needs to fully
            // mask the static half underneath while it's mid-rotation, or
            // the old digit bleeds through the new one and reads as a
            // double-exposed "ghost" during the flip. In glass mode it
            // fills with the same `FlapColors.frostedCard` tone as the
            // resting halves, so the opaque flap is visually indistinct
            // from the resting card and the flip doesn't change the card's
            // appearance at all.
            FlipCardLayer(value: value, cardSize: cardSize, isDark: isDark, glassCard: glassCard, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont) {
                bottomValue = value
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

/// Opaque frosted-tone base for a glass-style card. This replaces the
/// per-card behind-window `NSVisualEffectView` that glass cards used to
/// draw: a live blur can't be matched by the static rasterized flap, so
/// the flip flashed. A flat opaque frosted tone (shared with the flap) is
/// what makes resting and mid-flip identical.
///
/// It's a real `NSView` rather than a SwiftUI `Color` specifically so it
/// can override `mouseDownCanMoveWindow` — the desktop overlay window is
/// `isMovableByWindowBackground`, and this base view tiles across nearly
/// the whole widget, so it has to report itself draggable or the widget
/// can't be moved by dragging over the digits. (This is the same reason
/// the old per-card blur subclassed `NSVisualEffectView`; that blur is
/// gone, but the drag requirement remains.)
private struct DraggableColorView: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> NSView {
        let view = DraggableColorNSView()
        view.wantsLayer = true
        view.cardColor = NSColor(color)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DraggableColorNSView)?.cardColor = NSColor(color)
    }
}

private final class DraggableColorNSView: NSView {
    var cardColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = cardColor.cgColor
    }
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
    var tint: Color? = nil

    private var coreHeight: CGFloat { compact ? 1.5 : 3.5 }

    var body: some View {
        Rectangle()
            .fill(FlapColors.leafHinge(isDark: isDark, tint: tint))
            .frame(width: width, height: coreHeight)
    }
}
