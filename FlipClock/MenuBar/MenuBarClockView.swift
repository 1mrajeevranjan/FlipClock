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

    var body: some View {
        SplitFlapClockFace(
            tick: timeProvider.tick,
            scale: 1,
            compact: true,
            meridiemStyle: settings.meridiemStyle,
            timeFormat: settings.timeFormat,
            fontName: settings.widgetFont.postscriptName
        )
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
