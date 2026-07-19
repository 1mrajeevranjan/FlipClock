import SwiftUI

/// Compact split-flap render sized for the ~22pt status bar.
struct MenuBarClockView: View {
    /// Total status-item size this view needs for a given time format —
    /// computed the same way as `SplitFlapClockFace.idealSize`
    /// (analytically, not measured), since `NSStatusItem`/`NSHostingView`
    /// sizing must be set explicitly before the view has done a layout
    /// pass.
    static func itemSize(timeFormat: TimeFormat) -> CGSize {
        SplitFlapClockFace.idealSize(scale: 1, compact: true, showMeridiem: timeFormat == .twelveHour)
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    /// Overrides `settings.theme` while a reminder is due and
    /// unacknowledged — `StatusItemController` flips this between
    /// `.light`/`.dark` every 5s. Fed into `SplitFlapClockFace` as an
    /// explicit `isDarkOverride` *parameter*, not `.preferredColorScheme()`
    /// — confirmed (the hard way) that `.preferredColorScheme()`'s
    /// environment value doesn't reliably re-propagate to
    /// `@Environment(\.colorScheme)` reads further down the tree on
    /// updates when this view is hosted inside an `NSStatusItem` button,
    /// even though plain view parameters (proven with a diagnostic
    /// background-color toggle) update correctly in that same context.
    var pulseColorScheme: ColorScheme? = nil

    var body: some View {
        SplitFlapClockFace(
            tick: timeProvider.tick,
            scale: 1,
            compact: true,
            meridiemStyle: settings.meridiemStyle,
            timeFormat: settings.timeFormat,
            fontName: settings.widgetFont.postscriptName,
            isDarkOverride: pulseColorScheme.map { $0 == .dark }
        )
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
