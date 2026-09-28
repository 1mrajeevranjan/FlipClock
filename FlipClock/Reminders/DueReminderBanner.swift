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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityAddTraits(.isHeader)

            ForEach(reminders) { reminder in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.callout.weight(.medium))
                        Text(Self.timeFormatter.string(from: reminder.date))
                            .font(.caption2)
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
                    // HIG 11.1: an icon-only button needs a spoken label.
                    .accessibilityLabel("Acknowledge \(reminder.title)")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
    }
}
