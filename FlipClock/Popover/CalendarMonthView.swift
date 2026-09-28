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
    /// The day under the pointer, for its hover highlight (HIG 6.1) — set
    /// immediately, unlike the debounced reminder preview above.
    @State private var hoveredCell: Date? = nil

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

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
    }

    /// Space between week rows. The reminder dot sits inside this gap, below
    /// its date, instead of reserving its own strip under every date — that
    /// strip made rows uneven and left the bottom margin visibly deeper than
    /// the top.
    private static let rowSpacing: CGFloat = 8
    private static let daySize: CGFloat = 24

    var body: some View {
        // One 7-column `Grid` for the header, weekday letters and dates, so
        // everything shares the same columns: the arrows sit centred over the
        // first and last day columns, and the title over the middle five. As
        // separate stacks the arrows drifted out of line with the dates.
        Grid(horizontalSpacing: 0, verticalSpacing: Self.rowSpacing) {
            GridRow {
                NavButton(systemName: "chevron.left", label: "Previous Month", shortcut: .leftArrow) { shiftMonth(by: -1) }
                    .frame(maxWidth: .infinity)
                titleCell
                    .gridCellColumns(5)
                    .frame(maxWidth: .infinity)
                NavButton(systemName: "chevron.right", label: "Next Month", shortcut: .rightArrow) { shiftMonth(by: 1) }
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 4)

            GridRow {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(index == sundayColumn ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { column, day in
                        dayCell(day, column: column)
                    }
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

    /// Month title, plus a way back to the current month once you've wandered
    /// off it (Calendar-app convention).
    private var titleCell: some View {
        HStack(spacing: 8) {
            Text(Self.titleFormatter.string(from: displayedMonth))
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if !isShowingCurrentMonth {
                Button("Today") { displayedMonth = calendar.startOfMonth(for: today) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Go to today (⌘T)")
            }
        }
    }

    private func dayCell(_ day: Int?, column: Int) -> some View {
        Group {
            if let day {
                let cellDate = date(for: day)
                let cellReminders = reminderStore.reminders(on: cellDate)
                Text("\(day)")
                    .font(.callout.weight(isToday(day) ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(textColor(day: day, column: column))
                    .frame(width: Self.daySize, height: Self.daySize)
                    .background(dayBackground(day: day, date: cellDate))
                    .clipShape(Circle())
                    // Drawn in the row gap below the date (see `rowSpacing`),
                    // so it costs no layout height.
                    .overlay(alignment: .bottom) {
                        if !cellReminders.isEmpty {
                            ReminderBadge(isDue: calendar.isDateInToday(cellDate) && cellReminders.contains { !$0.isAcknowledged }, diameter: 5)
                                .offset(y: Self.rowSpacing - 1)
                        }
                    }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { addingReminderFor = cellDate }
                // HIG 6.2: the double-click action, discoverable on right-click.
                .contextMenu {
                    Button("Add Reminder…") { addingReminderFor = cellDate }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: cellDate, reminderCount: cellReminders.count))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Add Reminder") { addingReminderFor = cellDate }
                .onHover { isHovering in
                    hoveredCell = isHovering ? cellDate : (hoveredCell == cellDate ? nil : hoveredCell)
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
                Color.clear
                    .frame(height: Self.daySize)
                    .frame(maxWidth: .infinity)
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

    /// Today is marked in the user's accent colour (HIG 9.3), as macOS
    /// Calendar does. Sunday keeps its own colour — system red, the same
    /// Sunday marker the desktop widget's weekday row uses — so the week's
    /// start stands out as its own column.
    private func textColor(day: Int, column: Int) -> Color {
        if isToday(day) { return .white }
        return column == sundayColumn ? .red : .primary
    }

    private func dayBackground(day: Int, date: Date) -> Color {
        if isToday(day) { return .accentColor }
        return hoveredCell == date ? Color.primary.opacity(0.08) : .clear
    }

    /// Column index of Sunday within the (possibly rotated) week row —
    /// Foundation's `weekday` component is 1 = Sunday...7 = Saturday.
    private var sundayColumn: Int {
        (1 - calendar.firstWeekday + 7) % 7
    }

    private static let spokenDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    private func accessibilityLabel(for date: Date, reminderCount: Int) -> String {
        var parts = [Self.spokenDateFormatter.string(from: date)]
        if calendar.isDate(date, inSameDayAs: today) { parts.append("today") }
        if reminderCount > 0 { parts.append(reminderCount == 1 ? "1 reminder" : "\(reminderCount) reminders") }
        return parts.joined(separator: ", ")
    }

    private func shiftMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func isToday(_ day: Int) -> Bool {
        guard isShowingCurrentMonth else { return false }
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

    /// `dayCells` padded out to whole weeks and split into rows of 7.
    private var weeks: [[Int?]] {
        let cells = dayCells
        let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }
}

/// Chevron step button matching the native macOS look — no border, subtle
/// circular highlight on hover, secondary-color glyph (Rule 6.1: every
/// interactive element needs a visible hover state), a spoken label and
/// tooltip (11.1), and a ⌘-arrow shortcut (5.1).
private struct NavButton: View {
    let systemName: String
    let label: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(isHovered ? Color.primary.opacity(0.08) : .clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(label) (⌘\(shortcut == .leftArrow ? "←" : "→"))")
        .accessibilityLabel(label)
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
