import SwiftUI

/// Current-month calendar grid with prev/next navigation arrows on either
/// side of the month title, matching a typical menu-bar calendar widget.
struct CalendarMonthView: View {
    @ObservedObject var reminderStore: ReminderStore

    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())
    /// The day currently showing the "New Reminder" popover, or `nil` if
    /// none is open — set by a double-click on a day cell.
    @State private var addingReminderFor: Date? = nil
    /// The day currently showing the hover preview popover — separate from
    /// `addingReminderFor` so the two can never fight over the same
    /// presentation state. `nil` means no hover card is showing.
    @State private var hoveredDate: Date? = nil
    /// Debounces hover-in so a fast mouse sweep across a whole week row
    /// doesn't flash a popover open-then-closed on every cell it crosses —
    /// only the cell the pointer actually settles on for a moment gets one.
    @State private var hoverTask: Task<Void, Never>? = nil

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private let weekdaySymbols: [String] = {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }()

    /// Column index of Sunday within the (possibly rotated) week row —
    /// Foundation's `weekday` component is 1 = Sunday...7 = Saturday.
    private var sundayColumn: Int {
        (1 - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                NavButton(systemName: "chevron.left", action: { shiftMonth(by: -1) })
                Spacer()
                Text(Self.titleFormatter.string(from: displayedMonth))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                NavButton(systemName: "chevron.right", action: { shiftMonth(by: 1) })
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(index == sundayColumn ? .red : .secondary)
                }
                ForEach(Array(dayCells.enumerated()), id: \.offset) { index, day in
                    dayCell(day, column: index % 7)
                }
            }
        }
        // A `.popover` triggered from *inside* content that's already
        // itself presented as a popover (this whole view lives inside
        // `PopoverClockView`, hosted via `NSPopover`) doesn't reliably
        // present — confirmed live, it silently did nothing on hover. This
        // overlay is plain inline SwiftUI content in the same view tree,
        // not a second presentation layer, so it can't fail that way.
        .overlay(alignment: .top) {
            if let hoveredDate, let reminders = hoveredReminders, !reminders.isEmpty {
                ReminderHoverCard(date: hoveredDate, reminders: reminders)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    )
                    .offset(y: -8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredDate)
    }

    private var hoveredReminders: [Reminder]? {
        guard let hoveredDate else { return nil }
        return reminderStore.reminders(on: hoveredDate)
    }

    private func dayCell(_ day: Int?, column: Int) -> some View {
        Group {
            if let day {
                let cellDate = date(for: day)
                let cellReminders = reminderStore.reminders(on: cellDate)
                VStack(spacing: 2) {
                    Text("\(day)")
                        .font(.system(size: 12, weight: isToday(day) ? .bold : .regular))
                        .foregroundStyle(textColor(day: day, column: column))
                        .frame(width: 22, height: 22)
                        .background(isToday(day) ? Color.primary : Color.clear)
                        .clipShape(Circle())
                    // Reserve the mark's height even when empty so every
                    // row of the grid stays the same height regardless of
                    // which days happen to have reminders.
                    if !cellReminders.isEmpty {
                        ReminderBadge(isDue: calendar.isDateInToday(cellDate) && cellReminders.contains { !$0.isAcknowledged }, diameter: 5)
                    } else {
                        Color.clear.frame(width: 5, height: 5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { addingReminderFor = cellDate }
                .onHover { isHovering in
                    hoverTask?.cancel()
                    guard isHovering, !cellReminders.isEmpty else {
                        if hoveredDate == cellDate { hoveredDate = nil }
                        return
                    }
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        guard !Task.isCancelled else { return }
                        hoveredDate = cellDate
                    }
                }
                .popover(isPresented: Binding(
                    get: { addingReminderFor == cellDate },
                    set: { isPresented in if !isPresented { addingReminderFor = nil } }
                )) {
                    AddReminderView(
                        date: cellDate,
                        onSave: { title, preciseDate in
                            reminderStore.add(title: title, date: preciseDate)
                            addingReminderFor = nil
                        },
                        onCancel: { addingReminderFor = nil }
                    )
                }
            } else {
                Color.clear.frame(width: 22, height: 22 + 2 + 5)
            }
        }
    }

    /// The actual `Date` a grid day number represents, combined from
    /// `displayedMonth`'s year/month and the cell's day-of-month.
    private func date(for day: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        comps.day = day
        return calendar.date(from: comps) ?? displayedMonth
    }

    private func textColor(day: Int, column: Int) -> Color {
        if isToday(day) {
            return invertedPrimary
        }
        return column == sundayColumn ? .red : .primary
    }

    private func shiftMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    /// `Color.primary`'s own inverse — white text on the dark circle in
    /// light mode, black text on the light circle in dark mode.
    private var invertedPrimary: Color {
        colorScheme == .dark ? .black : .white
    }

    private func isToday(_ day: Int) -> Bool {
        guard calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month) else { return false }
        return day == calendar.component(.day, from: today)
    }

    /// Leading `nil`s pad the grid so day 1 lands in the correct weekday
    /// column, followed by 1...daysInMonth.
    private var dayCells: [Int?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        return Array(repeating: nil, count: leadingBlanks) + range.map { Optional($0) }
    }
}

/// Chevron step button matching the native macOS look — no border, subtle
/// circular highlight on hover, secondary-color glyph (Rule 6.1: every
/// interactive element needs a visible hover state).
private struct NavButton: View {
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(isHovered ? Color.primary.opacity(0.08) : .clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

/// Hover preview for a day that has one or more reminders — read-only (no
/// acknowledge/edit controls, those live in the "Due Today" banner and the
/// double-click "New Reminder" form respectively). This is purely "what's
/// on this day and when."
private struct ReminderHoverCard: View {
    let date: Date
    let reminders: [Reminder]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var sortedReminders: [Reminder] {
        reminders.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dateFormatter.string(from: date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(sortedReminders) { reminder in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("@ \(Self.timeFormatter.string(from: reminder.date))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(reminder.isAcknowledged ? .secondary : .primary)
                    Text(reminder.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .strikethrough(reminder.isAcknowledged)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
    }
}
