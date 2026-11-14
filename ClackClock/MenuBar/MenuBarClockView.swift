import SwiftUI

/// Compact split-flap render sized for the ~22pt status bar.
struct MenuBarClockView: View {
    /// Total status-item size this view needs for a given time format —
    /// computed the same way as `SplitFlapClockFace.idealSize`
    /// (analytically, not measured), since `NSStatusItem`/`NSHostingView`
    /// sizing must be set explicitly before the view has done a layout
    /// pass.
    static func itemSize(timeFormat: TimeFormat, meridiemStyle: MeridiemStyle = .text, display: MenuBarDisplay = .time) -> CGSize {
        switch display {
        case .time:
            return SplitFlapClockFace.idealSize(scale: 1, compact: true, showMeridiem: timeFormat == .twelveHour,
                                                meridiemCards: meridiemStyle.cards(isPM: false).count)
        case .date:
            return CGSize(width: dateCardSize.width * 2 + dateDigitSpacing + datePadding * 2, height: dateCardSize.height)
        }
    }

    /// Same card as the compact clock face, so switching modes only drops cards.
    private static let dateCardSize = CGSize(width: 14, height: 20)
    private static let dateDigitSpacing: CGFloat = 2
    private static let datePadding: CGFloat = 4

    /// Always two cards ("05"), so the item keeps one width all month.
    static func dayDigits(of date: Date, calendar: Calendar = .current) -> (tens: Int, ones: Int) {
        let day = calendar.component(.day, from: date)
        return (day / 10, day % 10)
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        // Status-item hosting doesn't reliably propagate preferredColorScheme.
        let isDark = settings.theme.resolvedColorScheme(system: systemColorScheme) == .dark
        switch settings.menuBarDisplay {
        case .time:
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: 1,
                compact: true,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                fontName: settings.widgetFont.postscriptName,
                isDarkOverride: isDark
            )
        case .date:
            let day = Self.dayDigits(of: timeProvider.tick.date)
            SplitFlapPairView(
                tens: day.tens, ones: day.ones,
                cardSize: Self.dateCardSize, digitSpacing: Self.dateDigitSpacing,
                isDark: isDark, compact: true,
                fontName: settings.widgetFont.postscriptName
            )
            .padding(.horizontal, Self.datePadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timeProvider.tick.date.formatted(date: .complete, time: .omitted))
        }
    }
}
