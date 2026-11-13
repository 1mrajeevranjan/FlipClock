import AppKit

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

    /// Used for both the reminder alarm and the Settings preview. "Default" follows
    /// the user's system alert sound (System Settings › Sound).
    func alarm() -> NSSound? {
        if let url { return NSSound(contentsOf: url, byReference: true) }
        return UserDefaults.standard.string(forKey: "com.apple.sound.beep.sound")
            .flatMap { NSSound(contentsOfFile: $0, byReference: true) }
            ?? NSSound(named: "Glass")
    }
}
