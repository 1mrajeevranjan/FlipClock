import SwiftUI

/// Root content of the desktop overlay window: a plain rectangular
/// split-flap face sized like a normal macOS desktop widget — no
/// pedestal/chrome, since that "physical object on a stand" look reads as
/// oversized and out of place next to Calendar/Weather-style widgets.
/// Optionally shows the day/date/month/year above the clock.
struct OverlayContentView: View {
    static let padding: CGFloat = 22
    static let dateSpacing: CGFloat = 10

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    /// Total window content size for this view at a given scale/date
    /// visibility — computed analytically (see
    /// `SplitFlapClockFace.idealSize`) rather than measured via AppKit,
    /// since fitting-size queries aren't reliable on the same runloop turn
    /// the hosting view is attached to a window.
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateSize = showDate ? dateRowSize(scale: scale) : .zero
        let width = max(face.width, dateSize.width) + padding * 2
        let height = face.height + (showDate ? dateSpacing + dateSize.height : 0) + padding * 2
        return CGSize(width: width, height: height)
    }

    private static func dateRowSize(scale: CGFloat) -> CGSize {
        DateFlapRow.idealSize(scale: scale)
    }

    /// Full-screen mode gets a noticeably larger clock to better fill the
    /// extra space a whole-screen layout affords.
    private var effectiveScale: CGFloat {
        settings.overlaySize.scale * (settings.fillScreen ? 1.6 : 1.0)
    }

    var body: some View {
        VStack(spacing: Self.dateSpacing) {
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: effectiveScale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                glassCard: true
            )

            if settings.showDateOnOverlay {
                DateFlapRow(date: timeProvider.tick.date, scale: effectiveScale, isDark: colorScheme == .dark, glassCard: true)
            }
        }
        .padding(Self.padding)
        // Center explicitly instead of relying on the hosting window's
        // frame to match this content's natural size exactly — any drift
        // between the analytic `windowSize()` estimate and SwiftUI's real
        // layout (e.g. worst-case weekday width vs. today's actual
        // weekday) otherwise pins content to the window's top-left corner
        // instead of centering it, producing lopsided margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen))
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

private struct DateFlapRow: View {
    let date: Date
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEEE"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "MMM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "dd"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "yyyy"
        return f
    }()

    private var weekdayCharacters: [String] {
        Array(Self.weekdayFormatter.string(from: date).uppercased()).map(String.init)
    }

    private var dateGroups: [[String]] {
        [
            Array(Self.monthFormatter.string(from: date).uppercased()).map(String.init),
            Array(Self.dayFormatter.string(from: date)).map(String.init),
            Array(Self.yearFormatter.string(from: date)).map(String.init)
        ]
    }

    private var cardSize: CGSize {
        CGSize(width: 46, height: 74).scaled(scale)
    }

    private var digitGap: CGFloat { 5 * scale }
    private var groupGap: CGFloat { 14 * scale }
    private var rowGap: CGFloat { 6 * scale }

    private var weekdayColor: NSColor? {
        Calendar.current.component(.weekday, from: date) == 1 ? .systemRed : nil
    }

    var body: some View {
        VStack(spacing: rowGap) {
            HStack(spacing: digitGap) {
                ForEach(Array(weekdayCharacters.enumerated()), id: \.offset) { _, character in
                    SplitFlapDigit(
                        value: character,
                        cardSize: cardSize,
                        isDark: isDark,
                        compact: false,
                        textColor: weekdayColor,
                        glassCard: glassCard
                    )
                }
            }

            HStack(spacing: groupGap) {
                ForEach(Array(dateGroups.enumerated()), id: \.offset) { _, group in
                    HStack(spacing: digitGap) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                            SplitFlapDigit(
                                value: character,
                                cardSize: cardSize,
                                isDark: isDark,
                                compact: false,
                                glassCard: glassCard
                            )
                        }
                    }
                }
            }
        }
    }

    static func idealSize(scale: CGFloat) -> CGSize {
        let cardSize = CGSize(width: 46, height: 74).scaled(scale)
        let digitGap: CGFloat = 5 * scale
        let groupGap: CGFloat = 14 * scale
        let rowGap: CGFloat = 6 * scale
        let maxWeekdayCharacters: CGFloat = 9
        let dateCharacters: CGFloat = 9 // "MMM" + "dd" + "yyyy" = 3 + 2 + 4
        let weekdayWidth = cardSize.width * maxWeekdayCharacters + digitGap * (maxWeekdayCharacters - 1)
        let dateWidth = cardSize.width * dateCharacters + digitGap * (dateCharacters - 3) + groupGap * 2
        return CGSize(width: max(weekdayWidth, dateWidth), height: cardSize.height * 2 + rowGap)
    }
}

private extension CGSize {
    func scaled(_ scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}
