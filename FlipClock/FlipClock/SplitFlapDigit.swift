import SwiftUI

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

    @State private var topValue: String
    @State private var bottomValue: String

    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        _topValue = State(initialValue: value)
        _bottomValue = State(initialValue: value)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HalfCard(image: DigitFaceRenderer.halfFace(for: topValue, cardSize: cardSize, top: true, isDark: isDark, textColor: textColor))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
                HalfCard(image: DigitFaceRenderer.halfFace(for: bottomValue, cardSize: cardSize, top: false, isDark: isDark, textColor: textColor))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
            }
            HingeLine(width: cardSize.width, isDark: isDark, compact: compact)

            FlipCardLayer(value: value, cardSize: cardSize, isDark: isDark) {
                bottomValue = value
            }
            .frame(width: cardSize.width, height: cardSize.height)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 2 : 6))
        .onChange(of: value) { _, newValue in
            topValue = newValue
        }
    }
}

private struct HalfCard: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
    }
}

/// The seam between the two half-cards, built as shadow → bold line →
/// highlight rather than one flat rule — that's what reads as an actual
/// physical gap/fold instead of a printed stripe.
private struct HingeLine: View {
    let width: CGFloat
    let isDark: Bool
    let compact: Bool

    private var edgeBand: CGFloat { compact ? 1 : 3 }
    private var coreHeight: CGFloat { compact ? 1 : 2.5 }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, shadowColor], startPoint: .top, endPoint: .bottom)
                .frame(height: edgeBand)
            Rectangle()
                .fill(FlapColors.leafHinge(isDark: isDark))
                .frame(height: coreHeight)
            LinearGradient(colors: [highlightColor, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: edgeBand)
        }
        .frame(width: width)
    }

    // Softer than the first pass — HIG favors subtle depth cues over
    // heavy contrast; the stronger values read as a harsh painted line
    // rather than a shadowed physical gap.
    private var shadowColor: Color { .black.opacity(isDark ? 0.4 : 0.22) }
    private var highlightColor: Color { .white.opacity(isDark ? 0.08 : 0.4) }
}
