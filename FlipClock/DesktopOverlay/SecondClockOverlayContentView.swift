import SwiftUI

/// Root content of the second desktop clock widget — mirrors
/// `OverlayContentView`'s glass-widget look but renders
/// `settings.secondTimezoneID` instead of the system timezone, with a
/// small timezone label above the clock face so it reads as distinct from
/// the primary widget at a glance. Day/date/year row and general styling
/// (size, font, color style, theme) all follow the same settings as the
/// default clock, per product intent — this isn't a separately configured
/// widget, just the same one pointed at another timezone.
struct SecondClockOverlayContentView: View {
    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @ObservedObject var backdropCapture: DesktopBackdropCapture
    @Environment(\.colorScheme) private var colorScheme

    private var timeZone: TimeZone { TimeZone(identifier: settings.secondTimezoneID) ?? .current }

    private var tick: ClockTick {
        ClockTick.at(date: timeProvider.tick.date, calendar: ClockTick.calendar(for: timeZone))
    }

    private var timezoneLabel: String { Self.timezoneLabel(for: settings.secondTimezoneID) }

    /// City/region name portion of a timezone identifier, formatted the
    /// same way for the view and for `windowSize` (which needs it to size
    /// the window without constructing a whole view).
    static func timezoneLabel(for identifier: String) -> String {
        let timeZone = TimeZone(identifier: identifier) ?? .current
        let name = timeZone.identifier.components(separatedBy: "/").last ?? timeZone.identifier
        return name.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var effectiveScale: CGFloat { settings.overlaySize.scale }

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
                    timeFormat: settings.timeFormat,
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
        .background(WidgetGlassBackground(scale: effectiveScale, backdropImage: backdropCapture.image, monochrome: settings.widgetDrainsColor))
        .preferredColorScheme(settings.theme.colorScheme)
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
