import SwiftUI

struct CalendarNavigation {
    enum Level { case days, months, years }

    let calendar: Calendar
    private(set) var displayedMonth: Date
    var selectedDate: Date
    private(set) var level: Level = .days

    init(date: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        selectedDate = calendar.startOfDay(for: date)
    }

    var year: Int { calendar.component(.year, from: displayedMonth) }

    var yearPage: ClosedRange<Int> {
        let start = ((year - 1) / 12) * 12 + 1
        return start...min(start + 11, 9999)
    }

    var months: [Date] {
        guard let start = calendar.dateInterval(of: .year, for: displayedMonth)?.start,
              let range = calendar.range(of: .month, in: .year, for: displayedMonth) else { return [] }
        return range.compactMap { calendar.date(byAdding: .month, value: $0 - range.lowerBound, to: start) }
    }

    var weeks: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - range.lowerBound, to: displayedMonth) }
        let cells = Array<Date?>(repeating: nil, count: blanks) + dates.map { Optional($0) }
        let padded = cells + Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }

    mutating func showLargerRange() {
        switch level {
        case .days: level = .months
        case .months: level = .years
        case .years: break
        }
    }

    mutating func showSmallerRange(today: Date = Date()) {
        switch level {
        case .years: level = .months
        case .months: self = CalendarNavigation(date: today, calendar: calendar)
        case .days: break
        }
    }

    func pageTarget(by direction: Int) -> Date? {
        let target: Date?
        if level == .years {
            var components = calendar.dateComponents([.era, .month], from: displayedMonth)
            components.year = yearPage.lowerBound + direction * 12
            components.day = 1
            target = calendar.date(from: components)
        } else {
            target = calendar.date(byAdding: level == .days ? .month : .year, value: direction, to: displayedMonth)
        }
        guard let date = target,
              (1...9999).contains(calendar.component(.year, from: date)),
              calendar.component(.era, from: date) == calendar.component(.era, from: displayedMonth) else { return nil }
        return date
    }

    mutating func page(by direction: Int) {
        guard let date = pageTarget(by: direction) else { return }
        selectedDate = level == .days
            ? (calendar.date(byAdding: .month, value: direction, to: selectedDate) ?? date)
            : date
        displayedMonth = date
    }

    mutating func chooseYear(_ year: Int) {
        guard (1...9999).contains(year) else { return }
        var components = calendar.dateComponents([.era, .month], from: displayedMonth)
        components.year = year
        components.day = 1
        guard let date = calendar.date(from: components) else { return }
        displayedMonth = date
        selectedDate = date
        level = .months
    }

    mutating func chooseMonth(_ date: Date) {
        guard calendar.isDate(date, equalTo: displayedMonth, toGranularity: .year),
              let start = calendar.dateInterval(of: .month, for: date)?.start else { return }
        displayedMonth = start
        selectedDate = start
        level = .days
    }
}

struct CalendarMonthView: View {
    @ObservedObject var reminderStore: ReminderStore
    @Binding var navigation: CalendarNavigation
    var today = Date()
    var isVisible = true
    @State private var addingReminderFor: Date?
    @State private var hoveredDate: Date?
    @State private var hoveredCell: Date?
    @State private var hoverTask: Task<Void, Never>?
    @State private var presentationID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { navigation.calendar }
    private static let rowSpacing: CGFloat = 8
    private static let daySize: CGFloat = 30
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var title: String {
        switch navigation.level {
        case .days: return navigation.displayedMonth.formatted(.dateTime.month(.wide).year())
        case .months: return String(navigation.year)
        case .years: return "\(navigation.yearPage.lowerBound)–\(navigation.yearPage.upperBound)"
        }
    }

    private var pageUnit: String {
        switch navigation.level {
        case .days: return "month"
        case .months: return "year"
        case .years: return "12 years"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if let date = addingReminderFor {
                // Inline presentation avoids unreliable nested NSPopovers and fits the form's height.
                AddReminderView(date: date, onSave: { title, preciseDate in
                    reminderStore.add(title: title, date: preciseDate)
                    addingReminderFor = nil
                }, onCancel: { addingReminderFor = nil })
            } else {
                navigationHeader
                switch navigation.level {
                case .days: dayGrid
                case .months: monthGrid
                case .years: yearGrid
                }
                if navigation.level == .days {
                    Divider()
                    HStack {
                        Text(navigation.selectedDate, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { addingReminderFor = navigation.selectedDate } label: {
                            Label("Add Reminder", systemImage: "plus")
                        }
                        .popoverActionButton(prominent: true)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                        .tint(.blue)
                        .environment(\.controlActiveState, .active)
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Add reminder for the selected date (⌘N)")
                    }
                }
            }
        }
        .modifier(PopoverEntrance(trigger: presentationID))
        .onChange(of: navigation.displayedMonth) { _, _ in clearHover(); presentationID += 1 }
        .onChange(of: navigation.level) { _, _ in clearHover(); presentationID += 1 }
        .onChange(of: addingReminderFor) { _, _ in presentationID += 1 }
        .onDisappear(perform: clearHover)
        .accessibilityActions {
            if navigation.level != .days {
                Button(navigation.level == .years ? "Back to months" : "Back to today’s calendar") {
                    navigation.showSmallerRange()
                }
            }
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            CalendarNavButton(systemName: "chevron.left", label: "Previous \(pageUnit)", shortcut: .leftArrow) {
                navigation.page(by: -1)
            }
            .disabled(navigation.pageTarget(by: -1) == nil)
            Spacer(minLength: 0)
            Group {
                if navigation.level == .years {
                    Text(title)
                } else {
                    Button { navigation.showLargerRange() } label: {
                        Text(title)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityHint(navigation.level == .days ? "Show months" : "Show years")
                    .help(navigation.level == .days ? "Choose a month; click again to choose a year" : "Choose a year")
                }
            }
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(height: 32)
            Spacer(minLength: 0)
            CalendarNavButton(systemName: "chevron.right", label: "Next \(pageUnit)", shortcut: .rightArrow) {
                navigation.page(by: 1)
            }
            .disabled(navigation.pageTarget(by: 1) == nil)
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(navigation.months, id: \.self) { month in
                CalendarSelectionButton(title: month.formatted(.dateTime.month(.abbreviated)),
                                        isSelected: calendar.isDate(month, equalTo: navigation.displayedMonth, toGranularity: .month)) {
                    navigation.chooseMonth(month)
                }
                .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
            }
        }
    }

    private var yearGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(navigation.yearPage), id: \.self) { year in
                CalendarSelectionButton(title: String(year), isSelected: year == navigation.year) {
                    navigation.chooseYear(year)
                }
            }
        }
    }

    private var dayGrid: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let weekdays = Array(symbols[first...] + symbols[..<first])
        return Grid(horizontalSpacing: 0, verticalSpacing: Self.rowSpacing) {
            GridRow {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { column, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(column == sundayColumn ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(navigation.weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { column, date in
                        dayCell(date, column: column)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let hoveredDate {
                let reminders = reminderStore.reminders(on: hoveredDate)
                if !reminders.isEmpty {
                    ReminderHoverCard(date: hoveredDate, reminders: reminders)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                        .offset(y: -8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredDate)
    }

    @ViewBuilder
    private func dayCell(_ date: Date?, column: Int) -> some View {
        if let date {
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isSelected = calendar.isDate(date, inSameDayAs: navigation.selectedDate)
            let reminders = reminderStore.reminders(on: date)
            Button { navigation.selectedDate = date } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : (isToday ? .blue : (column == sundayColumn ? .red : .primary)))
                    .frame(width: Self.daySize, height: Self.daySize)
                    .background(isSelected ? Color.accentColor : Color.primary.opacity(hoveredCell == date ? 0.08 : 0), in: Circle())
                    .overlay(alignment: .bottom) {
                        if !reminders.isEmpty {
                            ReminderBadge(isDue: isToday && reminders.contains { !$0.isAcknowledged }, diameter: 5, isActive: isVisible)
                                .offset(y: Self.rowSpacing - 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PopoverPressStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { addingReminderFor = date })
            .contextMenu { Button("Add Reminder…") { addingReminderFor = date } }
            .accessibilityLabel(accessibilityLabel(for: date, reminderCount: reminders.count))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Add Reminder") { addingReminderFor = date }
            .onHover { hovering in
                hoveredCell = hovering ? date : (hoveredCell == date ? nil : hoveredCell)
                hoverTask?.cancel()
                hoveredDate = nil
                guard hovering, !reminders.isEmpty else { return }
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled else { return }
                    hoveredDate = date
                }
            }
        } else {
            Color.clear.frame(height: Self.daySize).frame(maxWidth: .infinity)
        }
    }

    private var sundayColumn: Int { (1 - calendar.firstWeekday + 7) % 7 }

    private func clearHover() {
        hoverTask?.cancel()
        hoveredDate = nil
        hoveredCell = nil
    }

    private func accessibilityLabel(for date: Date, reminderCount: Int) -> String {
        var parts = [date.formatted(date: .complete, time: .omitted)]
        if calendar.isDate(date, inSameDayAs: today) { parts.append("today") }
        if reminderCount > 0 { parts.append("\(reminderCount) reminders") }
        return parts.joined(separator: ", ")
    }
}

private struct CalendarNavButton: View {
    let systemName: String
    let label: String
    let shortcut: KeyEquivalent
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
                .modifier(PopoverControlSurface(tint: Color.primary.opacity(isHovered ? 0.06 : 0), cornerRadius: 16))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(label) (⌘\(shortcut == .leftArrow ? "←" : "→"))")
        .accessibilityLabel(label)
    }
}

private struct CalendarSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovered ? 0.08 : 0.025),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(PopoverPressStyle())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ReminderHoverCard: View {
    let date: Date
    let reminders: [Reminder]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(reminders.sorted { $0.date < $1.date }) { reminder in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reminder.date, format: .dateTime.hour().minute())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(reminder.title)
                        .font(.callout)
                        .strikethrough(reminder.isAcknowledged)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
    }
}
