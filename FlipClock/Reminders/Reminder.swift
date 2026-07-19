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
}
