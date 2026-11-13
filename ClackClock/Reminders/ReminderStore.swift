import Foundation

/// Single source of truth for user-created reminders, persisted as JSON in
/// UserDefaults — mirrors `AppSettings`' persistence style; the list is
/// never large enough to need real storage. One instance is created in
/// `AppDelegate` and shared by the calendar popover, the desktop widget,
/// and the menu bar clock so all three surfaces agree on what's due, what's
/// upcoming, and what's already been acknowledged.
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []

    private var calendar: Calendar { .current }
    private let key = "reminders"
    /// Injectable so tests can pass an isolated `UserDefaults(suiteName:)`
    /// instead of touching the real user's `.standard`.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func reminders(on date: Date) -> [Reminder] {
        reminders.filter { !$0.isAcknowledged && calendar.isDate($0.date, inSameDayAs: date) }
    }

    func add(title: String, date: Date) {
        reminders.append(Reminder(date: date, title: title))
        save()
    }

    func remove(_ reminder: Reminder) {
        guard reminders.contains(where: { $0.id == reminder.id }) else { return }
        reminders.removeAll { $0.id == reminder.id }
        save()
    }

    func acknowledge(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }),
              !reminders[index].isAcknowledged else { return }
        reminders[index].isAcknowledged = true
        save()
    }

    /// Reminders due today that haven't been acknowledged yet — what
    /// drives the popover's Due Today banner and the widget's flash.
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

    var widgetReminders: [Reminder] {
        let today = dueTodayUnacknowledged
        return (today.isEmpty ? upcomingWithin24Hours : today).sorted { $0.date < $1.date }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: key)
    }
}
