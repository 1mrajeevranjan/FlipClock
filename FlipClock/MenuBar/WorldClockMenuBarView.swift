import SwiftUI
import AppKit

/// A world clock's menu-bar item: a small name tag ("TOKYO") beside compact
/// split-flap digits, so every extra clock says which zone it is — the
/// unlabelled one is local time. The digits reuse the primary
/// `TimeProvider`'s already-captured `Date` (via `ClockTick.at`) rather than
/// calling `Date()` again, so the menu-bar clocks never drift apart.
struct WorldClockMenuBarView: View {
    static let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let labelSpacing: CGFloat = 3

    /// Measured, not left to layout: the status item's length has to be set
    /// before SwiftUI has laid anything out (same reason as
    /// `MenuBarClockView.itemSize`).
    static func itemSize(label: String, timeFormat: TimeFormat) -> CGSize {
        let clock = SplitFlapClockFace.idealSize(scale: 1, compact: true, showMeridiem: timeFormat == .twelveHour, showSeconds: false)
        let labelWidth = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
        return CGSize(width: labelWidth + labelSpacing + clock.width, height: clock.height)
    }

    let timeProvider: TimeProvider
    let clock: WorldClock
    @ObservedObject var settings: AppSettings

    private var tick: ClockTick {
        ClockTick.at(date: timeProvider.tick.date, calendar: ClockTick.calendar(for: clock.timeZone))
    }

    var body: some View {
        HStack(spacing: Self.labelSpacing) {
            // Left to the menu bar's own appearance (no forced colour
            // scheme) so the tag always matches the other menu-bar text.
            Text(clock.menuBarLabel)
                .font(Font(Self.labelFont))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            SplitFlapClockFace(
                tick: tick,
                scale: 1,
                compact: true,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: clock.timeFormat,
                fontName: settings.widgetFont.postscriptName,
                // An explicit parameter rather than `.preferredColorScheme` —
                // that environment value doesn't reliably reach views hosted
                // in a status item (see `MenuBarClockView.pulseColorScheme`),
                // and it would also have forced the name tag's colour.
                isDarkOverride: settings.theme.colorScheme.map { $0 == .dark },
                // Menu-bar room is scarce on a notched MacBook (macOS hides
                // items that don't fit, behind the notch), and seconds are
                // identical in every zone.
                showSeconds: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock.displayName) time")
    }
}
