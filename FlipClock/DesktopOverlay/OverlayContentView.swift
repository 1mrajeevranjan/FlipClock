import SwiftUI

/// Root content of the desktop overlay window: a plain rectangular
/// split-flap face sized like a normal macOS desktop widget — no
/// pedestal/chrome, since that "physical object on a stand" look reads as
/// oversized and out of place next to Calendar/Weather-style widgets.
/// Optionally shows the day/date/month/year above the clock.
struct OverlayContentView: View {
    static let padding: CGFloat = 20
    static let dateSpacing: CGFloat = 10

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings

    /// Total window content size for this view at a given scale/date
    /// visibility — computed analytically (see
    /// `SplitFlapClockFace.idealSize`) rather than measured via AppKit,
    /// since fitting-size queries aren't reliable on the same runloop turn
    /// the hosting view is attached to a window.
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateHeight: CGFloat = showDate ? dateFontSize(scale: scale) * 1.4 + dateSpacing : 0
        return CGSize(width: face.width + padding * 2, height: face.height + dateHeight + padding * 2)
    }

    private static func dateFontSize(scale: CGFloat) -> CGFloat {
        max(11, 13 * scale)
    }

    var body: some View {
        VStack(spacing: Self.dateSpacing) {
            if settings.showDateOnOverlay {
                DateHeaderView(date: timeProvider.tick.date, showYear: true, fontSize: Self.dateFontSize(scale: settings.overlaySize.scale))
            }
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: settings.overlaySize.scale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat
            )
        }
        .padding(Self.padding)
        .background(.clear)
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
