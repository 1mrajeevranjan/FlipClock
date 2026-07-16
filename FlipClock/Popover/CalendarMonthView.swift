import SwiftUI

/// Current-month calendar grid with prev/next navigation arrows on either
/// side of the month title, matching a typical menu-bar calendar widget.
struct CalendarMonthView: View {
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())

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
    }

    private func dayCell(_ day: Int?, column: Int) -> some View {
        Group {
            if let day {
                Text("\(day)")
                    .font(.system(size: 12, weight: isToday(day) ? .bold : .regular))
                    .foregroundStyle(textColor(day: day, column: column))
                    .frame(width: 22, height: 22)
                    .background(isToday(day) ? Color.primary : Color.clear)
                    .clipShape(Circle())
            } else {
                Color.clear.frame(width: 22, height: 22)
            }
        }
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
