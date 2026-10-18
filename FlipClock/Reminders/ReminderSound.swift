import AppKit
import UserNotifications

struct ReminderSound: Identifiable, Hashable {
    let id: String
    let label: String
    private let url: URL?

    static let systemDefault = ReminderSound(id: "default", label: "Default", url: nil)
    static let all: [ReminderSound] = [systemDefault] +
        (Bundle.main.urls(forResourcesWithExtension: "aiff", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ReminderSound(id: $0.lastPathComponent, label: $0.deletingPathExtension().lastPathComponent, url: $0) }

    static func byID(_ id: String) -> Self {
        all.first { $0.id == id } ?? .systemDefault
    }

    var notificationSound: UNNotificationSound {
        url == nil ? .default : UNNotificationSound(named: UNNotificationSoundName(rawValue: id))
    }

    func preview() -> NSSound? {
        guard let url else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }
}
