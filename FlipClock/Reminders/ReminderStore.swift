import Foundation
import Combine

/// Single source of truth for user-created reminders, persisted as JSON in
/// UserDefaults — mirrors `AppSettings`' persistence style; the list is
/// never large enough to need real storage. One instance is created in
/// `AppDelegate` and shared by the calendar popover, the desktop widget,
/// and the menu bar clock so all three surfaces agree on what's due, what's
/// upcoming, and what's already been acknowledged.
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []

    private let calendar = Calendar.current
    private let key = "reminders"

    init() {
        load()
    }

    func reminders(on date: Date) -> [Reminder] {
        reminders.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func hasReminder(on date: Date) -> Bool {
        !reminders(on: date).isEmpty
    }

    func add(title: String, date: Date) {
        reminders.append(Reminder(date: date, title: title))
        save()
    }

    func remove(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        save()
    }

    func acknowledge(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index].isAcknowledged = true
        save()
    }

    /// Acknowledges every reminder due today at once — used when the user
    /// dismisses the menu bar's pulse without opening the popover to
    /// individually check each one off.
    func acknowledgeAllDueToday() {
        var changed = false
        for index in reminders.indices where calendar.isDateInToday(reminders[index].date) && !reminders[index].isAcknowledged {
            reminders[index].isAcknowledged = true
            changed = true
        }
        if changed { save() }
    }

    /// Reminders due today that haven't been acknowledged yet — what
    /// drives the menu bar's light/dark pulse and the widget's stronger
    /// flash.
    var dueTodayUnacknowledged: [Reminder] {
        reminders.filter { calendar.isDateInToday($0.date) && !$0.isAcknowledged }
    }

    /// Reminders landing within the next 24 hours but not yet today —
    /// what drives the softer "upcoming" mark on the calendar and widget,
    /// distinct from the due-today pulse.
    var upcomingWithin24Hours: [Reminder] {
        let now = Date()
        guard let cutoff = calendar.date(byAdding: .hour, value: 24, to: now) else { return [] }
        return reminders.filter {
            !$0.isAcknowledged && !calendar.isDateInToday($0.date) && $0.date > now && $0.date <= cutoff
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
