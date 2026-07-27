import SwiftUI

private enum PopoverTab: String, CaseIterable, Identifiable {
    case calendar, timer, stopwatch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendar: return "Calendar"
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        }
    }
}

/// Full popover content, now split into three tabs (Calendar / Timer /
/// Stopwatch) via a top icon+label tab row — a Mac-idiomatic stand-in for
/// the "separate tab per tool" structure of iOS's Clock app (World Clock/
/// Alarms/Stopwatch/Timers). A literal bottom iOS tab bar is a documented
/// Mac anti-pattern (Mac apps use toolbars/segmented controls, not bottom
/// tab bars), so this reuses `SettingsView`'s own tab-row pattern instead
/// of a `Picker(.segmented)` — macOS's segmented control style silently
/// drops the icon from a `Label` and renders text-only, so a custom row
/// was the only way to actually show the SF Symbols.
///
/// Width is derived from `SplitFlapClockFace.idealSize` — the same
/// analytic-size approach used for the desktop overlay and menu bar item
/// — and stays constant across all three tabs; only height changes
/// per tab, matching the fix applied to `SettingsView` (varying width
/// too made switching feel like it was sliding sideways).
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
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var timerModel: CountdownTimer
    @ObservedObject var stopwatch: Stopwatch

    @State private var selectedTab: PopoverTab = .calendar

    var body: some View {
        VStack(spacing: 16) {
            tabRow

            switch selectedTab {
            case .calendar:
                calendarContent
            case .timer:
                CountdownTimerView(timerModel: timerModel, settings: settings)
            case .stopwatch:
                StopwatchView(stopwatch: stopwatch, settings: settings)
            }
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

    private var tabRow: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15))
                        Text(tab.label)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(selectedTab == tab ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                )
            }
        }
    }

    private var calendarContent: some View {
        VStack(spacing: 16) {
            DateHeaderView(date: timeProvider.tick.date)

            if !reminderStore.dueTodayUnacknowledged.isEmpty {
                DueReminderBanner(reminders: reminderStore.dueTodayUnacknowledged) { reminder in
                    reminderStore.acknowledge(reminder)
                }
            }

            // `showOwnGlassPanel: false` — this view already sits on
            // `VibrantHostingController`'s own blur; a second independent
            // `NSVisualEffectView` per card just grays everything out
            // instead of compositing (confirmed visually). `glassCard`
            // still gets the cards transparent digit rendering and the
            // matching translucent/shadowless flip animation, so they
            // read as glass sitting on the popover's existing vibrancy.
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: Self.clockScale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                glassCard: true,
                showOwnGlassPanel: false,
                fontName: settings.widgetFont.postscriptName
            )
            CalendarMonthView(reminderStore: reminderStore)
        }
    }
}
