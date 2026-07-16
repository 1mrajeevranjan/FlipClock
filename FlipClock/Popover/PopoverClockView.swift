import SwiftUI

/// Full popover content: today's date, the split-flap clock (no pedestal —
/// that's the desktop overlay's "physical object" look, not popover UI
/// chrome), and a month calendar with prev/next navigation.
///
/// Width is derived from `SplitFlapClockFace.idealSize` — the same
/// analytic-size approach used for the desktop overlay and menu bar item.
/// The previous version hardcoded both the clock's `scale` and the
/// popover's `width` independently (2.4 and 320), which didn't actually
/// agree: the clock's real rendered width at that scale was already ~320pt
/// *before* the 20pt padding on each side was added, so it overflowed the
/// popover and ran off-screen.
struct PopoverClockView: View {
    private static let clockScale: CGFloat = 0.8
    private static let padding: CGFloat = 20

    static var width: CGFloat {
        // Sized for the meridiem card present (12-hour, the wider case) so
        // the popover never needs to resize if the user switches formats.
        SplitFlapClockFace.idealSize(scale: clockScale, compact: false, showPedestal: false, showMeridiem: true).width + padding * 2
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 18) {
            DateHeaderView(date: timeProvider.tick.date)
            SplitFlapClockFace(tick: timeProvider.tick, scale: Self.clockScale, compact: false, showPedestal: false, meridiemStyle: settings.meridiemStyle, timeFormat: settings.timeFormat)
            CalendarMonthView()
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        // Explicit clear (not omitted) — NSHostingController's view
        // defaults to an opaque background otherwise, which would sit on
        // top of VibrantHostingController's blur+scrim and hide both
        // completely. This is the SwiftUI-level way to make it
        // transparent; doing it via `hostedView.layer` directly from
        // VibrantHostingController broke `.preferredColorScheme`
        // reactivity for this view.
        .background(Color.clear)
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
