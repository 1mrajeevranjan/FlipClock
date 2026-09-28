import SwiftUI

/// Root content of a world clock's desktop widget — the main widget's glass
/// look, pointed at another time zone, with the clock's name as a small row
/// of flip cards above the digits so it reads as distinct from the main
/// widget at a glance. Size and 12/24-hour format are the clock's own;
/// font, theme, colour style and the date row follow the main clock.
struct WorldClockOverlayContentView: View {
    let clockID: WorldClock.ID
    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @ObservedObject var backdropCapture: DesktopBackdropCapture
    @ObservedObject var visibility: WindowVisibility
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Falls back to a placeholder for the single frame between the clock
    /// being removed and its window being torn down.
    private var clock: WorldClock {
        settings.worldClocks.first { $0.id == clockID } ?? WorldClock(timezoneID: TimeZone.current.identifier)
    }

    private var timeZone: TimeZone { clock.timeZone }

    private var tick: ClockTick {
        ClockTick.at(date: visibility.tick(from: timeProvider).date, calendar: ClockTick.calendar(for: timeZone))
    }

    private var timezoneLabel: String { Self.flapLabel(for: clock) }

    /// The name as the flip-card row renders it — shared with `windowSize`,
    /// which has to size the window without building a view.
    static func flapLabel(for clock: WorldClock) -> String {
        clock.displayName.uppercased()
    }

    private var effectiveScale: CGFloat { clock.widgetSize.scale }

    /// Strictly follows the app's theme setting, same as every other
    /// surface — see `OverlayContentView.effectiveIsDark`.
    private var effectiveIsDark: Bool { colorScheme == .dark }

    private static func labelSpacing(scale: CGFloat) -> CGFloat { (8 * scale).clamped(to: 6...12) }

    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool, timezoneLabel: String) -> CGSize {
        let base = OverlayContentView.windowSize(scale: scale, showDate: showDate, showMeridiem: showMeridiem)
        let labelSize = TimezoneFlapRow.idealSize(for: timezoneLabel, scale: scale)
        return CGSize(
            width: max(base.width, labelSize.width),
            height: base.height + labelSize.height + labelSpacing(scale: scale)
        )
    }

    var body: some View {
        VStack(spacing: Self.labelSpacing(scale: effectiveScale)) {
            // Same flip-card style/size as the day/date row below it — a
            // plain `Text` label read as too low-contrast against the
            // widget's glass background to tell timezones apart at a
            // glance.
            TimezoneFlapRow(
                label: timezoneLabel,
                scale: effectiveScale,
                isDark: effectiveIsDark,
                glassCard: true,
                fontName: settings.widgetFont.postscriptName
            )

            VStack(spacing: OverlayContentView.dateSpacing(scale: effectiveScale)) {
                SplitFlapClockFace(
                    tick: tick,
                    scale: effectiveScale,
                    compact: false,
                    showPedestal: false,
                    meridiemStyle: settings.meridiemStyle,
                    timeFormat: clock.timeFormat,
                    glassCard: true,
                    fontName: settings.widgetFont.postscriptName,
                    isDarkOverride: effectiveIsDark
                )

                if settings.showDateOnOverlay {
                    DateFlapRow(
                        date: tick.date,
                        scale: effectiveScale,
                        isDark: effectiveIsDark,
                        glassCard: true,
                        fontName: settings.widgetFont.postscriptName,
                        timeZone: timeZone
                    )
                }
            }
        }
        .padding(OverlayContentView.padding(scale: effectiveScale))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            WidgetGlassBackground(scale: effectiveScale, backdropImage: backdropCapture.image, dimmedBackdropImage: backdropCapture.dimmedImage, tone: settings.widgetGlassTone)
                // The fade between vivid and dimmed the system's own widgets do
                // when an app comes to the front or the wallpaper is clicked.
                .animation(reduceMotion ? nil : GlassTone.transition, value: settings.widgetGlassTone)
        )
        .environment(\.glassTone, settings.widgetGlassTone)
        .preferredColorScheme(settings.theme.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock.displayName): \(OverlayContentView.spokenTime(tick.date, showDate: settings.showDateOnOverlay, timeZone: timeZone))")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Renders a timezone name as a row of split-flap cards, one per
/// character, grouped by word (space-separated) the same way
/// `DateFlapRow`'s month/day/year groups are — same card size/gap
/// constants as that row, so it visually matches the day/date row
/// directly beneath it.
private struct TimezoneFlapRow: View {
    /// The label reads as a small caption above the clock, not another
    /// full-size flap row — 60% smaller than `DateFlapRow`'s cards, whose
    /// gap constants this otherwise mirrors.
    static let labelScaleFactor: CGFloat = 0.4

    let label: String
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false
    var fontName: String? = nil

    private var wordGroups: [[String]] {
        label.components(separatedBy: " ").filter { !$0.isEmpty }.map { Array($0).map(String.init) }
    }

    private var effectiveScale: CGFloat { scale * Self.labelScaleFactor }
    private var cardSize: CGSize { CGSize(width: 46 * effectiveScale, height: 74 * effectiveScale) }
    private var digitGap: CGFloat { 5 * effectiveScale }
    private var groupGap: CGFloat { 14 * effectiveScale }

    var body: some View {
        HStack(spacing: groupGap) {
            ForEach(Array(wordGroups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: digitGap) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                        SplitFlapDigit(
                            value: character,
                            cardSize: cardSize,
                            isDark: isDark,
                            compact: false,
                            glassCard: glassCard,
                            fontName: fontName
                        )
                    }
                }
            }
        }
    }

    static func idealSize(for label: String, scale: CGFloat) -> CGSize {
        let effectiveScale = scale * labelScaleFactor
        let cardSize = CGSize(width: 46 * effectiveScale, height: 74 * effectiveScale)
        let digitGap: CGFloat = 5 * effectiveScale
        let groupGap: CGFloat = 14 * effectiveScale
        let groups: [Int] = label.components(separatedBy: " ").filter { !$0.isEmpty }.map { $0.count }
        guard !groups.isEmpty else { return .zero }
        let totalChars: Int = groups.reduce(0, +)
        let gapCount: Int = max(0, totalChars - groups.count)
        let charsWidth: CGFloat = CGFloat(totalChars) * cardSize.width
        let gapsWidth: CGFloat = CGFloat(gapCount) * digitGap
        let groupGapsWidth: CGFloat = CGFloat(groups.count - 1) * groupGap
        let width: CGFloat = charsWidth + gapsWidth + groupGapsWidth
        return CGSize(width: width, height: cardSize.height)
    }
}
