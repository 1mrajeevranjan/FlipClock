import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case calendar, timer, stopwatch
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String { rawValue }
    var color: Color {
        switch self {
        case .calendar: return .accentColor
        case .timer: return .orange
        case .stopwatch: return .teal
        }
    }
}

final class PopoverPresentation: ObservableObject {
    @Published var selectedTab: PopoverTab = .calendar {
        didSet { updateDisplayActivity() }
    }
    @Published private(set) var isPresented = false
    @Published var calendarNavigation: CalendarNavigation
    @Published private(set) var today: Date
    private var frozenTick: ClockTick
    private let timerModel: CountdownTimer
    private let stopwatch: Stopwatch

    init(timeProvider: TimeProvider, timerModel: CountdownTimer, stopwatch: Stopwatch, date: Date = Date()) {
        frozenTick = timeProvider.tick
        calendarNavigation = CalendarNavigation(date: date)
        today = Calendar.current.startOfDay(for: date)
        self.timerModel = timerModel
        self.stopwatch = stopwatch
        updateDisplayActivity()
    }

    func setPresented(_ presented: Bool, timeProvider: TimeProvider, date: Date = Date()) {
        if presented { refreshCalendar(date: date, resetSelection: true) }
        if !presented { frozenTick = timeProvider.tick }
        isPresented = presented
        updateDisplayActivity()
    }

    func refreshCalendar(date: Date = Date(), resetSelection: Bool = false) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if resetSelection || day != today || calendar != calendarNavigation.calendar {
            calendarNavigation = CalendarNavigation(date: date, calendar: calendar)
        }
        if today != day { today = day }
    }

    func tick(from timeProvider: TimeProvider) -> ClockTick {
        isPresented ? timeProvider.tick : frozenTick
    }

    private func updateDisplayActivity() {
        timerModel.setDisplayActive(isPresented && selectedTab == .timer)
        stopwatch.setDisplayActive(isPresented && selectedTab == .stopwatch)
    }
}

struct PopoverClockView: View {
    private static let clockScale: CGFloat = 0.8
    private static let padding: CGFloat = 20

    static var width: CGFloat {
        SplitFlapClockFace.idealSize(scale: clockScale, compact: false, showPedestal: false, showMeridiem: true).width + padding * 2
    }

    let timeProvider: TimeProvider
    @ObservedObject var settings: AppSettings
    @ObservedObject var reminderStore: ReminderStore
    // Child tools observe their own ticks; the whole popover needn't redraw at 30 Hz.
    let timerModel: CountdownTimer
    let stopwatch: Stopwatch
    @ObservedObject var presentation: PopoverPresentation

    var body: some View {
        glassContent
            .padding(Self.padding)
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { presentation.calendarNavigation.showSmallerRange() }
                    .allowsHitTesting(presentation.selectedTab == .calendar && presentation.calendarNavigation.level != .days)
            }
            .preferredColorScheme(settings.theme.colorScheme)
            .onAppear { presentation.refreshCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))) { _ in
                presentation.refreshCalendar()
            }
    }

    @ViewBuilder
    private var glassContent: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            tabRow

            Group {
                switch presentation.selectedTab {
                case .calendar:
                    calendarContent
                case .timer:
                    CountdownTimerView(timerModel: timerModel, settings: settings)
                case .stopwatch:
                    StopwatchView(stopwatch: stopwatch, settings: settings)
                }
            }
            .modifier(PopoverEntrance(trigger: presentation.selectedTab))
        }
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(PopoverTab.allCases.enumerated()), id: \.element) { index, tab in
                PopoverTabButton(tab: tab, isSelected: presentation.selectedTab == tab) {
                    presentation.selectedTab = tab
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(tab.label) (⌘\(index + 1))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clock tools")
    }

    private var calendarContent: some View {
        VStack(spacing: 18) {
            PopoverClockHeader(timeProvider: timeProvider, settings: settings, presentation: presentation)
            if !reminderStore.dueTodayUnacknowledged.isEmpty {
                DueReminderBanner(reminders: reminderStore.dueTodayUnacknowledged) {
                    reminderStore.acknowledge($0)
                }
            }
            Divider()
            CalendarMonthView(reminderStore: reminderStore, navigation: $presentation.calendarNavigation,
                              today: presentation.today, isVisible: presentation.isPresented)
        }
    }

    private struct PopoverClockHeader: View {
        let timeProvider: TimeProvider
        @ObservedObject var settings: AppSettings
        @ObservedObject var presentation: PopoverPresentation

        var body: some View {
            let tick = presentation.tick(from: timeProvider)
            VStack(spacing: 12) {
                DateHeaderView(date: tick.date)
                SplitFlapClockFace(
                    tick: tick,
                    scale: PopoverClockView.clockScale,
                    compact: false,
                    showPedestal: false,
                    meridiemStyle: settings.meridiemStyle,
                    timeFormat: settings.timeFormat,
                    glassCard: true,
                    showOwnGlassPanel: false,
                    fontName: settings.widgetFont.postscriptName
                )
            }
        }
    }
}

private struct PopoverTabButton: View {
    let tab: PopoverTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(tab.label).foregroundStyle(.primary)
            } icon: {
                Image(systemName: tab.icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tab.color)
            }
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .modifier(PopoverControlSurface(tint: tab.color.opacity(isSelected ? 0.2 : (isHovered ? 0.07 : 0)), cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? tab.color.opacity(0.35) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
