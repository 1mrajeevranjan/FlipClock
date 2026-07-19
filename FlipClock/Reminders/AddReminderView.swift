import SwiftUI

/// Small form for creating a reminder on a specific calendar date —
/// presented as a popover anchored to the double-clicked day cell in
/// `CalendarMonthView`.
struct AddReminderView: View {
    let date: Date
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
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
        onSave(trimmed)
    }
}
