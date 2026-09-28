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

    /// Both buttons share one width, as in a standard macOS dialog.
    private static let buttonWidth: CGFloat = 72

    var body: some View {
        // One leading edge and one trailing edge for every row, a 16pt inset,
        // 12pt between groups and 2pt inside the title block (HIG 9.6). The
        // form rows sit in a two-column `Grid` so the labels share a column
        // and every control ends on the same trailing edge.
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Reminder")
                    .font(.headline)
                Text(Self.dateFormatter.string(from: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Title")
                        .foregroundStyle(.secondary)
                        // Leading, so the labels start on the same edge as
                        // the "New Reminder" heading above them.
                        .gridColumnAlignment(.leading)
                    TextField("Title", text: $title, prompt: Text("What's this for?"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($isFocused)
                        .onSubmit(save)
                }
                // The precise moment the reminder is due, separate from the
                // day it's filed under, so "due today" pulses land at a
                // meaningful time instead of whenever the day was
                // double-clicked. The stepper field is macOS's standard time
                // control: a bare `.field` picker left its digits floating
                // off-centre in an over-wide bezel.
                GridRow {
                    Text("Time")
                        .foregroundStyle(.secondary)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize()
                }
            }
            .font(.callout)

            HStack(spacing: 8) {
                Spacer()
                // HIG 5.3/5.4: Esc cancels, Return adds. Default push-button
                // chrome, not `.bordered` — that drew a heavy filled slab on
                // the popover's vibrancy.
                Button(action: onCancel) {
                    Text("Cancel").frame(width: Self.buttonWidth)
                }
                .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text("Add").frame(width: Self.buttonWidth)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
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
