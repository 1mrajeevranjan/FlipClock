import SwiftUI

/// Compact split-flap render for a second, user-chosen timezone — mirrors
/// `MenuBarClockView` but computes its `ClockTick` from
/// `settings.secondTimezoneID` instead of the local timezone. Reuses the
/// primary `TimeProvider`'s already-captured `Date` (via `ClockTick.at`)
/// rather than calling `Date()` again, so the two menu-bar clocks never
/// drift apart by a few milliseconds.
struct SecondClockMenuBarView: View {
    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings

    private var tick: ClockTick {
        let timeZone = TimeZone(identifier: settings.secondTimezoneID) ?? .current
        return ClockTick.at(date: timeProvider.tick.date, calendar: ClockTick.calendar(for: timeZone))
    }

    var body: some View {
        SplitFlapClockFace(
            tick: tick,
            scale: 1,
            compact: true,
            meridiemStyle: settings.meridiemStyle,
            timeFormat: settings.timeFormat,
            tintColor: settings.widgetTintEnabled ? settings.widgetTintColor : nil,
            fontName: settings.widgetFont.postscriptName,
            isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem
        )
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
