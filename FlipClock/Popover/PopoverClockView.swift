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

/// Full popover content, split into three tabs (Calendar / Timer /
/// Stopwatch, ⌘1-⌘3) via a top icon+label tab row — a Mac-idiomatic stand-in for
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
        // HIG 9.6: 20pt between groups (tab bar / content), 20pt margins.
        VStack(spacing: 20) {
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
        HStack(spacing: 4) {
            ForEach(Array(PopoverTab.allCases.enumerated()), id: \.element) { index, tab in
                PopoverTabButton(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
                // HIG 5.1: every mouse action has a keyboard equivalent.
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Popover sections")
    }

    private var calendarContent: some View {
        // Related pieces 8-12pt apart, the calendar as its own group 20pt below.
        VStack(spacing: 12) {
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
                .padding(.top, 8)
        }
    }
}

/// One section button in the popover's top row. Styled like macOS's own
/// icon-over-label tab rows (System Settings, Xcode inspectors) rather than
/// the old solid-accent slab with white text, which read as an iOS control:
/// the selected tab gets a quiet fill with its icon and label in the accent
/// colour; the others get a hover highlight (HIG 6.1). The icon sits in a
/// fixed-height frame so every label lands on the same baseline — the
/// symbols differ in height, which is what pushed "Calendar" out of line.
private struct PopoverTabButton: View {
    let tab: PopoverTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Text(tab.label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.1 : (isHovered ? 0.05 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
