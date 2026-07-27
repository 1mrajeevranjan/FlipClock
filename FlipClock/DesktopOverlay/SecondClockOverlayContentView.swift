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

    private var timezoneLabel: String {
        let name = timeZone.identifier.components(separatedBy: "/").last ?? timeZone.identifier
        return name.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var effectiveScale: CGFloat { settings.overlaySize.scale }

    private static func labelHeight(scale: CGFloat) -> CGFloat { (16 * scale).clamped(to: 12...22) }
    private static func labelSpacing(scale: CGFloat) -> CGFloat { (8 * scale).clamped(to: 6...12) }

    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool) -> CGSize {
        let base = OverlayContentView.windowSize(scale: scale, showDate: showDate, showMeridiem: showMeridiem)
        return CGSize(width: base.width, height: base.height + labelHeight(scale: scale) + labelSpacing(scale: scale))
    }

    var body: some View {
        VStack(spacing: Self.labelSpacing(scale: effectiveScale)) {
            Text(timezoneLabel)
                .font(.system(size: (13 * effectiveScale).clamped(to: 11...18), weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            VStack(spacing: OverlayContentView.dateSpacing(scale: effectiveScale)) {
                SplitFlapClockFace(
                    tick: tick,
                    scale: effectiveScale,
                    compact: false,
                    showPedestal: false,
                    meridiemStyle: settings.meridiemStyle,
                    timeFormat: settings.timeFormat,
                    glassCard: true,
                    fontName: settings.widgetFont.postscriptName
                )

                if settings.showDateOnOverlay {
                    DateFlapRow(
                        date: tick.date,
                        scale: effectiveScale,
                        isDark: colorScheme == .dark,
                        glassCard: true,
                        fontName: settings.widgetFont.postscriptName,
                        timeZone: timeZone
                    )
                }
            }
        }
        .padding(OverlayContentView.padding(scale: effectiveScale))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetGlassBackground(scale: effectiveScale, backdropImage: backdropCapture.image, monochrome: settings.widgetColorStyle == .monochrome))
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
