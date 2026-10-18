import SwiftUI

/// Root content of the desktop overlay window: a plain rectangular
/// split-flap face sized like a normal macOS desktop widget — no
/// pedestal/chrome, since that "physical object on a stand" look reads as
/// oversized and out of place next to Calendar/Weather-style widgets.
/// Optionally shows the day/date/month/year above the clock.
struct OverlayContentView: View {
    /// Concentric with the panel: outer radius = margin + card radius, so
    /// the cards' corners follow the widget's own curve instead of crowding
    /// it. At the default `.full` size (`scale = 0.65`, 22pt panel radius)
    /// this lands exactly on HIG's standard 16pt widget margin; the clamp
    /// only kicks in at the smallest/largest sizes.
    static func padding(scale: CGFloat) -> CGFloat {
        (WidgetGlassBackground.cornerRadius(scale: scale) - SplitFlapDigit.cardCornerRadius).clamped(to: 11...22)
    }

    static func dateSpacing(scale: CGFloat) -> CGFloat {
        (10 * scale).clamped(to: 7...14)
    }

    // ponytail: two rows keep the widget compact; the calendar holds the full list.
    static let maxVisibleReminders = 2

    static func reminderRowHeight(scale: CGFloat) -> CGFloat {
        ceil((12 * scale).clamped(to: 10...15) * 2.5)
    }

    static func reminderOverflowHeight(scale: CGFloat) -> CGFloat {
        ceil((10 * scale).clamped(to: 9...12) * 1.4)
    }

    static func reminderFooterHeight(scale: CGFloat, count: Int) -> CGFloat {
        let rows = min(max(0, count), maxVisibleReminders)
        guard rows > 0 else { return 0 }
        let overflow = count > maxVisibleReminders
        return CGFloat(rows) * reminderRowHeight(scale: scale) + CGFloat(rows - 1) * 4
            + (overflow ? 4 + reminderOverflowHeight(scale: scale) : 0)
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @ObservedObject var backdropCapture: DesktopBackdropCapture
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var visibility: WindowVisibility
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tick: ClockTick { visibility.tick(from: timeProvider) }

    private var reminders: [Reminder] { reminderStore.widgetReminders }

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
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool, reminderCount: Int = 0) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateSize = showDate ? dateRowSize(scale: scale) : .zero
        let contentPadding = padding(scale: scale)
        let footerHeight = reminderCount > 0 ? reminderFooterHeight(scale: scale, count: reminderCount) + dateSpacing(scale: scale) : 0
        let width = max(face.width, dateSize.width) + contentPadding * 2
        let height = footerHeight + face.height + (showDate ? dateSpacing(scale: scale) + dateSize.height : 0) + contentPadding * 2
        return CGSize(width: width, height: height)
    }

    private static func dateRowSize(scale: CGFloat) -> CGSize {
        DateFlapRow.idealSize(scale: scale)
    }

    private static let spokenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()

    /// What VoiceOver reads for the whole widget — otherwise it walks ~30
    /// unlabeled flap-card images one by one. Cached formatter because this
    /// is re-evaluated on every one-second tick.
    static func spokenTime(_ date: Date, showDate: Bool, timeZone: TimeZone = .current) -> String {
        spokenFormatter.timeZone = timeZone
        spokenFormatter.dateStyle = showDate ? .full : .none
        return spokenFormatter.string(from: date)
    }

    /// Full-screen mode gets a noticeably larger clock to better fill the
    /// extra space a whole-screen layout affords.
    private var effectiveScale: CGFloat {
        settings.overlaySize.scale * (settings.fillScreen ? 1.6 : 1.0)
    }

    var body: some View {
        VStack(spacing: Self.dateSpacing(scale: settings.overlaySize.scale)) {
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
                DateFlapRow(date: tick.date, scale: effectiveScale, isDark: effectiveIsDark, glassCard: true, fontName: settings.widgetFont.postscriptName)
                    .equatable()
            }
            if !reminders.isEmpty {
                ReminderFooter(reminders: reminders, now: tick.date, scale: effectiveScale)
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
        .background(
            WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen, backdropImage: backdropCapture.image, dimmedBackdropImage: backdropCapture.dimmedImage, tone: settings.widgetGlassTone)
                // The fade between vivid and dimmed the system's own widgets do
                // when an app comes to the front or the wallpaper is clicked.
                .animation(reduceMotion ? nil : GlassTone.transition, value: settings.widgetGlassTone)
        )
        .environment(\.glassTone, settings.widgetGlassTone)
        .preferredColorScheme(settings.theme.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibilityText: String {
        let time = Self.spokenTime(tick.date, showDate: settings.showDateOnOverlay)
        return ([time] + reminders.map { $0.summary(relativeTo: tick.date) }).joined(separator: ". ")
    }
}

private struct ReminderFooter: View {
    let reminders: [Reminder]
    let now: Date
    let scale: CGFloat
    @Environment(\.glassTone) private var tone
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Status colour only in full colour; Monochrome and dimmed widgets are
    /// single-colour throughout, like the system's.
    private func color(for reminder: Reminder) -> Color {
        guard tone == .vivid else { return Color(nsColor: FlapColors.glassGlyph(isDark: colorScheme == .dark, tone: tone)) }
        return reminder.date <= now ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(reminders.prefix(OverlayContentView.maxVisibleReminders))) { reminder in
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: (10 * scale).clamped(to: 9...12)))
                        .accessibilityHidden(true)
                    Text(reminder.summary(relativeTo: now))
                        .font(.system(size: (12 * scale).clamped(to: 10...15), weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(color(for: reminder))
                .frame(height: OverlayContentView.reminderRowHeight(scale: scale))
                .help(reminder.summary(relativeTo: now))
            }
            if reminders.count > OverlayContentView.maxVisibleReminders {
                Text("+\(reminders.count - OverlayContentView.maxVisibleReminders) more in calendar")
                    .font(.system(size: (10 * scale).clamped(to: 9...12)))
                    .foregroundStyle(Color(nsColor: FlapColors.glassGlyph(isDark: colorScheme == .dark, tone: tone)))
                    .frame(height: OverlayContentView.reminderOverflowHeight(scale: scale))
            }
        }
        .animation(reduceMotion ? nil : GlassTone.transition, value: tone)
    }
}

/// Day/date/year flap row shared by the primary desktop widget and the
/// second-timezone desktop widget — `timeZone` defaults to the system one
/// so existing call sites are unaffected; the second-clock widget passes
/// its own chosen timezone so the weekday/date reflect that zone's date,
/// not the system's (they can disagree near midnight).
struct DateFlapRow: View, Equatable {
    let date: Date
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false
    var fontName: String? = nil
    var timeZone: TimeZone = .current

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.scale == rhs.scale, lhs.isDark == rhs.isDark, lhs.glassCard == rhs.glassCard,
              lhs.fontName == rhs.fontName, lhs.timeZone == rhs.timeZone else { return false }
        var calendar = Calendar.current
        calendar.timeZone = lhs.timeZone
        return calendar.isDate(lhs.date, inSameDayAs: rhs.date)
    }

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
