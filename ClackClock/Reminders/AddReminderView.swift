import SwiftUI

struct AddReminderView: View {
    let date: Date
    let onSave: (String, Date) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var time = Date()
    @FocusState private var isFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Reminder")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(date, format: .dateTime.weekday(.abbreviated).day().month(.wide).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reminder")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("What would you like to remember?", text: $title)
                        .textFieldStyle(.plain)
                        .padding(9)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isFocused ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.15))
                        }
                        .focused($isFocused)
                        .accessibilityLabel("Reminder title")
                        .onSubmit(save)
                }
                HStack {
                    Text("Time").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize()
                }
            }

            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                    .popoverActionButton()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: save) {
                    Label("Add Reminder", systemImage: "plus")
                }
                .popoverActionButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PopoverCardSurface())
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let calendar = Calendar.current
        // Preserve the selected day when combining it with the time picker's clock time.
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let clockTime = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = clockTime.hour
        components.minute = clockTime.minute
        guard let combined = calendar.date(from: components) else { return }
        onSave(trimmedTitle, combined)
    }
}
