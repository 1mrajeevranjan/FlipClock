import Foundation

/// One user-created reminder anchored to a specific date. `date` carries
/// both the calendar day and (if the user set one) the time-of-day —
/// there's no separate "all-day" flag, a reminder just defaults to the
/// moment it was created at.
struct Reminder: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var title: String
    var isAcknowledged: Bool

    init(id: UUID = UUID(), date: Date, title: String, isAcknowledged: Bool = false) {
        self.id = id
        self.date = date
        self.title = title
        self.isAcknowledged = isAcknowledged
    }

    func summary(relativeTo now: Date, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else {
            day = date.formatted(date: .abbreviated, time: .omitted)
        }
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = calendar.timeZone
        return "\(day) @ \(date.formatted(format)) – \(title)"
    }
}
