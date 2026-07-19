import SwiftUI

/// Lists today's unacknowledged reminders inside the popover — this is
/// where the menu bar's light/dark pulse points the user to. Checking a
/// reminder off here (or via `ReminderStore.acknowledgeAllDueToday()` from
/// the menu bar itself) is what stops the pulse.
struct DueReminderBanner: View {
    let reminders: [Reminder]
    let onAcknowledge: (Reminder) -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Due Today", systemImage: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)

            ForEach(reminders) { reminder in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reminder.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(Self.timeFormatter.string(from: reminder.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onAcknowledge(reminder)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Acknowledge")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
    }
}
