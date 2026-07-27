import SwiftUI

/// Renders a sequence of two-digit time components (e.g. `[mm, ss]` or
/// `[hh, mm, ss]`) as real split-flap cards, separated by the same small
/// dot pair `SplitFlapClockFace` uses between its own groups — shared by
/// the countdown timer and the stopwatch so both flip digits down the
/// same way the clock does, in the user's selected font.
struct FlipTimeDisplay: View {
    let components: [Int]
    let isDark: Bool
    var fontName: String? = nil
    var cardSize: CGSize = CGSize(width: 30, height: 48)
    /// One label per component (e.g. `["hr", "min", "sec", "ms"]`) shown
    /// under its group — `nil` (the default) omits labels entirely, for
    /// contexts where the grouping is already obvious (the countdown
    /// timer, which only ever shows a clock-style HH:MM:SS).
    var unitLabels: [String]? = nil

    private let digitGap: CGFloat = 3
    private let groupGap: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: groupGap) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    separatorDots
                }
                VStack(spacing: 4) {
                    HStack(spacing: digitGap) {
                        digit(component / 10)
                        digit(component % 10)
                    }
                    if let label = unitLabels?[safe: index] {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func digit(_ value: Int) -> some View {
        SplitFlapDigit(
            value: String(value),
            cardSize: cardSize,
            isDark: isDark,
            compact: false,
            glassCard: true,
            showOwnGlassPanel: false,
            fontName: fontName
        )
    }

    /// Fixed to `cardSize.height` and vertically centered within that —
    /// groups with a unit label underneath are taller overall (digit row +
    /// label), but since the `HStack` aligns groups by their *top* edge,
    /// pinning this to just the digit row's height keeps the dots centered
    /// against the digits themselves rather than drifting down to split
    /// the difference with the label.
    private var separatorDots: some View {
        VStack(spacing: 3) {
            Circle().frame(width: 4)
            Circle().frame(width: 4)
        }
        .frame(height: cardSize.height)
        .foregroundStyle(FlapColors.separatorDot(isDark: isDark))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
