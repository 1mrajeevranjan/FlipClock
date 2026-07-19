import SwiftUI

/// Small pulsing dot used to flag a reminder that's due today or landing
/// within the next 24 hours — reused by both the desktop widget (a corner
/// badge) and the calendar day cells (a mark under the day number). Due
/// reminders pulse faster/more strongly than merely-upcoming ones, so the
/// escalation from "coming up" to "due now" reads without needing text.
struct ReminderBadge: View {
    var isDue: Bool
    var diameter: CGFloat = 8

    @State private var isPulsing = false

    private var color: Color { isDue ? .red : .orange }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .opacity(isPulsing ? 0.35 : 1)
            .scaleEffect(isPulsing ? 1.25 : 1)
            .animation(
                .easeInOut(duration: isDue ? 0.6 : 1.1).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
