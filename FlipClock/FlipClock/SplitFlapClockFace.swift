import SwiftUI
import AppKit

/// The full clock: HH : MM : SS split-flap pairs, an optional AM/PM flip
/// card (hidden in 24-hour format), and (optionally) the chrome pedestal
/// styling from the reference clock. `scale` drives every surface (menu
/// bar, popover, desktop overlay) from this single implementation;
/// `compact` trims sizing for the ~22pt menu bar rendering; `showPedestal`
/// is independent of `compact` — the desktop overlay wants the full
/// physical-clock look, the popover doesn't (it's UI chrome, not a
/// miniature desk object).
struct SplitFlapClockFace: View {
    let tick: ClockTick
    var scale: CGFloat = 1
    var compact: Bool = false
    var showPedestal: Bool = true
    var meridiemStyle: MeridiemStyle = .text
    var timeFormat: TimeFormat = .twelveHour

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    private var showMeridiem: Bool { timeFormat == .twelveHour }
    private var metrics: Metrics { Metrics(scale: scale, compact: compact, showPedestal: showPedestal, showMeridiem: showMeridiem) }

    var body: some View {
        let m = metrics
        let hour = tick.hourDigits(format: timeFormat)
        VStack(spacing: compact ? 0 : m.vGroupSpacing) {
            HStack(alignment: .center, spacing: m.rowSpacing) {
                SplitFlapPairView(tens: hour.tens, ones: hour.ones, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact)
                separator(m)
                SplitFlapPairView(tens: tick.minute / 10, ones: tick.minute % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact)
                separator(m)
                SplitFlapPairView(tens: tick.second / 10, ones: tick.second % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact)
                if showMeridiem {
                    SplitFlapDigit(value: meridiemStyle.value(isPM: tick.isPM), cardSize: m.ampmCardSize, isDark: isDark, compact: compact)
                }
            }

            if !compact && showPedestal {
                Pedestal(width: m.pedestalWidth)
                    .frame(height: 28 * scale)
            }
        }
        .padding(.horizontal, m.horizontalPadding)
    }

    /// Deterministic size mirroring the layout math in `body` exactly —
    /// callers that need to size an AppKit window/status item around this
    /// view use this instead of asking SwiftUI/AppKit to measure it.
    /// `NSHostingView.fittingSize` isn't reliably available on the same
    /// runloop turn the view is attached, and a hand-copied hardcoded
    /// frame silently drifts out of sync with the real layout — both bugs
    /// this project already hit once.
    static func idealSize(scale: CGFloat, compact: Bool, showPedestal: Bool = true, showMeridiem: Bool = true) -> CGSize {
        Metrics(scale: scale, compact: compact, showPedestal: showPedestal, showMeridiem: showMeridiem).totalSize
    }

    private func separator(_ m: Metrics) -> some View {
        VStack(spacing: m.separatorDotGap) {
            Circle().frame(width: m.separatorDotSize)
            Circle().frame(width: m.separatorDotSize)
        }
        .foregroundStyle(FlapColors.separatorDot(isDark: isDark))
    }
}

/// All layout numbers for one clock face, computed once from `scale` and
/// `compact` and shared between `body` (actual rendering) and
/// `idealSize` (window/status-item sizing) so the two can never disagree.
private struct Metrics {
    let scale: CGFloat
    let compact: Bool
    let showPedestal: Bool
    let showMeridiem: Bool

    var digitCardSize: CGSize {
        compact ? CGSize(width: 14, height: 20) : CGSize(width: 46, height: 74).scaled(scale)
    }

    var digitSpacing: CGFloat { compact ? 2 : 5 * scale }
    var rowSpacing: CGFloat { compact ? 4 : 14 * scale }
    var vGroupSpacing: CGFloat { 6 * scale }
    var separatorDotSize: CGFloat { compact ? 1.5 : 4 * scale }
    var separatorDotGap: CGFloat { compact ? 1 : 4 * scale }
    var horizontalPadding: CGFloat { compact ? 4 : 0 }

    var pairWidth: CGFloat { digitCardSize.width * 2 + digitSpacing }

    /// AM/PM as its own flip card — a real black-background card with the
    /// same flip animation as the digits, just "50% of the number height"
    /// as requested, sized to fit "AM"/"PM" at the same font formula
    /// `DigitFaceRenderer` uses (fullSize.height * 0.78) so the analytic
    /// width here matches what actually renders — the same class of bug
    /// fixed earlier for the digit cards, now applied to this card too.
    var ampmCardSize: CGSize {
        let height = digitCardSize.height * 0.5
        let fontSize = height * 0.78
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        // Measuring only the text glyphs — measuring the emoji ("☀️"/"🌙")
        // through the same heavy-weight NSFont produced a wildly wrong
        // advance width (color/bitmap emoji glyphs don't reliably report
        // sane metrics through this API at small point sizes), which
        // corrupted the whole status item's width. A fixed extra margin
        // covers the emoji case without measuring it directly.
        let widest = max(
            ("AM" as NSString).size(withAttributes: attrs).width,
            ("PM" as NSString).size(withAttributes: attrs).width
        )
        let width = widest * 1.3 + fontSize * 0.5
        return CGSize(width: width, height: height)
    }

    var pedestalWidth: CGFloat {
        digitCardSize.width * 6 + rowSpacing * 2 + separatorDotSize
    }

    var totalSize: CGSize {
        // 5 items without the meridiem card (HH, separator, MM, separator,
        // SS) = 4 gaps; the meridiem card adds a 6th item and 5th gap.
        let gaps = showMeridiem ? 5 : 4
        let meridiemWidth = showMeridiem ? ampmCardSize.width : 0
        let width = pairWidth * 3 + separatorDotSize * 2 + rowSpacing * CGFloat(gaps) + meridiemWidth + horizontalPadding * 2
        let rowHeight = digitCardSize.height
        let pedestalHeight = (!compact && showPedestal) ? vGroupSpacing + 28 * scale : 0
        let height = rowHeight + pedestalHeight
        return CGSize(width: width, height: height)
    }
}

private struct Pedestal: View {
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [FlapColors.chromeHighlight, FlapColors.chromeTop, FlapColors.chromeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.16, height: 14)
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [FlapColors.chromeHighlight, FlapColors.chromeBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width * 0.42, height: 16)
        }
    }
}

private extension CGSize {
    func scaled(_ scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}
