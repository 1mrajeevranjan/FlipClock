import SwiftUI
import AppKit

/// One flap position: a static top half, a static bottom half, and the
/// animating flap layered on top, all drawn by `FlipCardLayer`. Works for a
/// single digit ("7") or a short label ("AM") — same card, same flip
/// mechanism either way.
struct SplitFlapDigit: View {
    let value: String
    let cardSize: CGSize
    var isDark: Bool = true
    var compact: Bool = false
    var textColor: NSColor? = nil
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
    /// Glass card style: a translucent platter (`FlapColors.glassCardFill`)
    /// over whatever glass is behind the card, like the inner platters of
    /// macOS's own widgets, with its look following `\.glassTone`.
    var glassCard: Bool = false
    /// Retained for source compatibility with existing call sites; no
    /// longer affects rendering.
    var showOwnGlassPanel: Bool = true

    @Environment(\.glassTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil, fusedLeading: Bool = false, fusedTrailing: Bool = false, glassCard: Bool = false, showOwnGlassPanel: Bool = true, fontName: String? = nil, isMonospacedSystemFont: Bool = false) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        self.fusedLeading = fusedLeading
        self.fusedTrailing = fusedTrailing
        self.glassCard = glassCard
        self.showOwnGlassPanel = showOwnGlassPanel
        self.fontName = fontName
        self.isMonospacedSystemFont = isMonospacedSystemFont
    }

    static let cardCornerRadius: CGFloat = 6
    private var cornerRadius: CGFloat { compact ? 2 : Self.cardCornerRadius }
    /// Total seam-line thickness at rest — split between the top and
    /// bottom halves' baked-in slivers (see `DigitFaceRenderer.render`).
    /// Proportional to the card so the split between the two leaves stays a
    /// thin but clearly visible line at 2×/3× sizes, where a fixed 2.8pt all
    /// but vanished; floored so the smallest cards keep a readable seam.
    private var hingeThickness: CGFloat { compact ? 1.2 : max(2.4, cardSize.height * 0.024) }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: fusedLeading ? 0 : cornerRadius,
            bottomLeadingRadius: fusedLeading ? 0 : cornerRadius,
            bottomTrailingRadius: fusedTrailing ? 0 : cornerRadius,
            topTrailingRadius: fusedTrailing ? 0 : cornerRadius,
            style: .continuous
        )
    }

    /// Glass cards always get an explicit colour so the glyph follows the
    /// tone; a caller's accent (Sunday's red) only survives in full colour.
    private func glyphColor(for tone: GlassTone) -> NSColor? {
        guard glassCard else { return textColor }
        if let textColor, tone == .vivid { return textColor }
        return FlapColors.glassGlyph(isDark: isDark, tone: tone)
    }

    private func layerStyle(for tone: GlassTone) -> FlipCardLayer.Style {
        FlipCardLayer.Style(
            isDark: isDark,
            glassCard: glassCard,
            textColor: glyphColor(for: tone),
            tintsIcons: glassCard && tone != .vivid,
            fontName: fontName,
            isMonospacedSystemFont: isMonospacedSystemFont,
            hingeThickness: hingeThickness
        )
    }

    /// The looks this card can switch to from the current one — only glass
    /// cards change look at all.
    private var upcomingStyles: [FlipCardLayer.Style] {
        guard glassCard else { return [] }
        let current = layerStyle(for: tone)
        return [GlassTone.vivid, .dimmed].map(layerStyle(for:)).filter { $0 != current }
    }

    var body: some View {
        ZStack {
            if glassCard {
                cardShape
                    .fill(FlapColors.glassCardFill(isDark: isDark, tone: tone))
                    .animation(reduceMotion ? nil : GlassTone.transition, value: tone)
            }

            FlipCardLayer(
                value: value,
                cardSize: cardSize,
                style: layerStyle(for: tone),
                upcomingStyles: upcomingStyles
            )
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(cardShape)
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }
}
