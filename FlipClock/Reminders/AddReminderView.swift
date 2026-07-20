import SwiftUI

/// Small form for creating a reminder on a specific calendar date —
/// presented as a popover anchored to the double-clicked day cell in
/// `CalendarMonthView`.
struct AddReminderView: View {
    let date: Date
    let onSave: (String, Date) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var time: Date = Date()
    @FocusState private var isFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Reminder")
                .font(.system(size: 13, weight: .semibold))
            Text(Self.dateFormatter.string(from: date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("What's this reminder for?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)
            // "@ <time>" — the precise moment the reminder is due, separate
            // from the day it's filed under, so "due today" pulses/flashes
            // land at an actual meaningful time instead of whenever the
            // user happened to double-click the day cell.
            HStack(spacing: 6) {
                Text("@")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Button("Add", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear { isFocused = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Combine the picked day (`date`) with the picked time-of-day
        // (`time`) — `time`'s own date component is whatever day the
        // DatePicker defaulted to (today), which isn't necessarily the
        // reminder's actual day.
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        let combined = calendar.date(from: comps) ?? date
        onSave(trimmed, combined)
    }
}
