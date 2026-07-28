import SwiftUI

/// Root content of the desktop overlay window: a plain rectangular
/// split-flap face sized like a normal macOS desktop widget — no
/// pedestal/chrome, since that "physical object on a stand" look reads as
/// oversized and out of place next to Calendar/Weather-style widgets.
/// Optionally shows the day/date/month/year above the clock.
struct OverlayContentView: View {
    /// HIG's standard widget margin is 16pt; scaling it by `overlaySize`
    /// and clamping to `11...22` keeps the smallest widget from crowding
    /// its edges. At the default `.full` size (`scale = 0.65`) this floors
    /// at `11pt` — noticeably tighter than the old flat `22pt` constant, a
    /// deliberate move toward HIG's standard margin rather than an
    /// unchanged default.
    static func padding(scale: CGFloat) -> CGFloat {
        (16 * scale).clamped(to: 11...22)
    }

    static func dateSpacing(scale: CGFloat) -> CGFloat {
        (10 * scale).clamped(to: 7...14)
    }

    static func bannerHeight(scale: CGFloat) -> CGFloat {
        (16 * scale).clamped(to: 13...20)
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @ObservedObject var backdropCapture: DesktopBackdropCapture
    @ObservedObject var reminderStore: ReminderStore
    @Environment(\.colorScheme) private var colorScheme

    private var hasDueReminder: Bool { !reminderStore.dueTodayUnacknowledged.isEmpty }
    private var hasUpcomingReminder: Bool { !reminderStore.upcomingWithin24Hours.isEmpty }

    /// Due-today reminders take priority over merely-upcoming ones for the
    /// top banner — same escalation `ReminderBadge` uses (red = due now,
    /// orange = coming up within 24h).
    private var bannerGroup: (reminders: [Reminder], isDue: Bool)? {
        if hasDueReminder { return (reminderStore.dueTodayUnacknowledged, true) }
        if hasUpcomingReminder { return (reminderStore.upcomingWithin24Hours, false) }
        return nil
    }

    /// Digit/frost tone strictly follows the app's theme setting (or the
    /// system appearance, for `.system`) — same as every other surface.
    /// This intentionally does *not* factor in the sampled backdrop
    /// brightness: an earlier version derived it from
    /// `DesktopBackdropCapture.isDarkBackground` instead, which meant a
    /// dark wallpaper forced dark-mode text even with the app set to
    /// Light, ignoring the user's actual theme choice.
    private var effectiveIsDark: Bool { colorScheme == .dark }

    /// Total window content size for this view at a given scale/date
    /// visibility — computed analytically (see
    /// `SplitFlapClockFace.idealSize`) rather than measured via AppKit,
    /// since fitting-size queries aren't reliable on the same runloop turn
    /// the hosting view is attached to a window.
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool, hasReminderBanner: Bool = false) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateSize = showDate ? dateRowSize(scale: scale) : .zero
        let contentPadding = padding(scale: scale)
        let bannerHeight = hasReminderBanner ? Self.bannerHeight(scale: scale) + dateSpacing(scale: scale) : 0
        let width = max(face.width, dateSize.width) + contentPadding * 2
        let height = bannerHeight + face.height + (showDate ? dateSpacing(scale: scale) + dateSize.height : 0) + contentPadding * 2
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
        VStack(spacing: Self.dateSpacing(scale: settings.overlaySize.scale)) {
            if let bannerGroup {
                ReminderTopBanner(reminders: bannerGroup.reminders, isDue: bannerGroup.isDue, scale: effectiveScale)
            }

            SplitFlapClockFace(
                tick: timeProvider.tick,
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
                DateFlapRow(date: timeProvider.tick.date, scale: effectiveScale, isDark: effectiveIsDark, glassCard: true, fontName: settings.widgetFont.postscriptName)
            }
        }
        .padding(Self.padding(scale: settings.overlaySize.scale))
        // Center explicitly instead of relying on the hosting window's
        // frame to match this content's natural size exactly — any drift
        // between the analytic `windowSize()` estimate and SwiftUI's real
        // layout (e.g. worst-case weekday width vs. today's actual
        // weekday) otherwise pins content to the window's top-left corner
        // instead of centering it, producing lopsided margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen, backdropImage: backdropCapture.image, monochrome: settings.widgetColorStyle == .monochrome))
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

/// One-line reminder callout at the top of the desktop widget — replaces
/// the old top-trailing corner dot with something the user can actually
/// read without opening the popover. Due-today reminders show in red,
/// merely-upcoming ones in orange, matching `ReminderBadge`'s escalation.
private struct ReminderTopBanner: View {
    let reminders: [Reminder]
    let isDue: Bool
    let scale: CGFloat

    private var displayText: String {
        guard let first = reminders.first else { return "" }
        let extra = reminders.count - 1
        return extra > 0 ? "\(first.title) +\(extra)" : first.title
    }

    var body: some View {
        HStack(spacing: (6 * scale).clamped(to: 4...8)) {
            Image(systemName: "bell.fill")
                .font(.system(size: (11 * scale).clamped(to: 9...14)))
            Text(displayText)
                .font(.system(size: (12 * scale).clamped(to: 10...15), weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isDue ? Color.red : Color.orange)
    }
}

/// Day/date/year flap row shared by the primary desktop widget and the
/// second-timezone desktop widget — `timeZone` defaults to the system one
/// so existing call sites are unaffected; the second-clock widget passes
/// its own chosen timezone so the weekday/date reflect that zone's date,
/// not the system's (they can disagree near midnight).
struct DateFlapRow: View {
    let date: Date
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false
    var fontName: String? = nil
    var timeZone: TimeZone = .current

    // `DateFlapRow` is rebuilt every second (it's driven by `timeProvider.tick`),
    // and `body` reads `weekdayCharacters`/`dateGroups` — each of which used to
    // allocate a fresh `DateFormatter` per call, 4 allocations/second forever
    // while the overlay is visible, for values that only actually change once
    // a day. `DateFormatter` is expensive to construct (locale/calendar/
    // timezone resolution); caching by format string and just updating the
    // (cheap) timeZone property keeps this to one allocation per format ever.
    private static var formatterCache: [String: DateFormatter] = [:]

    private func formatter(_ dateFormat: String) -> DateFormatter {
        if let cached = Self.formatterCache[dateFormat] {
            cached.timeZone = timeZone
            return cached
        }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = timeZone
        f.dateFormat = dateFormat
        Self.formatterCache[dateFormat] = f
        return f
    }

    private var weekdayCharacters: [String] {
        Array(formatter("EEEE").string(from: date).uppercased()).map(String.init)
    }

    private var dateGroups: [[String]] {
        [
            Array(formatter("MMM").string(from: date).uppercased()).map(String.init),
            Array(formatter("dd").string(from: date)).map(String.init),
            Array(formatter("yyyy").string(from: date)).map(String.init)
        ]
    }

    private var cardSize: CGSize {
        CGSize(width: 46, height: 74).scaled(scale)
    }

    private var digitGap: CGFloat { 5 * scale }
    private var groupGap: CGFloat { 14 * scale }
    private var rowGap: CGFloat { 6 * scale }

    private var weekdayColor: NSColor? {
        var calendar = Self.baseCalendar
        calendar.timeZone = timeZone
        return calendar.component(.weekday, from: date) == 1 ? .systemRed : nil
    }

    private static let baseCalendar = Calendar.current

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
                        glassCard: glassCard,
                        fontName: fontName
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
                                glassCard: glassCard,
                                fontName: fontName
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
