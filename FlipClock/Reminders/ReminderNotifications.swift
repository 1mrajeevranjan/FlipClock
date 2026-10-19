import AppKit
import Combine
import UserNotifications

@MainActor
final class ReminderNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var statusMessage = "Enable alerts and sounds for timed reminders."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRequestingPermission = false

    private let store: ReminderStore
    private let settings: AppSettings
    private let center: UNUserNotificationCenter
    private var cancellables = Set<AnyCancellable>()
    private var schedulingTask: Task<Void, Never>?
    private var knownIDs: Set<UUID>
    private var newReminderIDs = Set<UUID>()
    private var previewSound: NSSound?
    nonisolated private static let prefix = "FlipClock-reminder-"
    nonisolated static let dismissActionIdentifier = "FlipClock-dismiss-reminder"

    nonisolated static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: "FlipClock-reminder", actions: [
            UNNotificationAction(identifier: dismissActionIdentifier, title: "Dismiss", options: [])
        ], intentIdentifiers: [], options: [.customDismissAction])
    }

    init(store: ReminderStore, settings: AppSettings, center: UNUserNotificationCenter = .current()) {
        self.store = store
        self.settings = settings
        self.center = center
        knownIDs = Set(store.reminders.map(\.id))
        super.init()
    }

    func start() {
        guard cancellables.isEmpty else { return }
        center.delegate = self
        center.setNotificationCategories([Self.category])
        store.$reminders.combineLatest(settings.$reminderSound)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reminders, sound in
                guard let self else { return }
                let ids = Set(reminders.map(\.id))
                self.newReminderIDs.formUnion(ids.subtracting(self.knownIDs))
                self.newReminderIDs.formIntersection(Set(reminders.filter { !$0.isAcknowledged }.map(\.id)))
                self.knownIDs = ids
                self.queue(reminders: reminders, sound: sound, requestPermission: !self.newReminderIDs.isEmpty)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        queue(reminders: store.reminders, sound: settings.reminderSound, requestPermission: false)
    }

    func enable() {
        guard !isRequestingPermission else { return }
        queue(reminders: store.reminders, sound: settings.reminderSound, requestPermission: true)
    }

    func playPreview(_ sound: ReminderSound) {
        previewSound?.stop()
        previewSound = sound.preview()
        previewSound?.play()
    }

    func handleResponse(actionIdentifier: String, requestIdentifier: String) {
        guard actionIdentifier == Self.dismissActionIdentifier || actionIdentifier == UNNotificationDismissActionIdentifier,
              requestIdentifier.hasPrefix(Self.prefix),
              let id = UUID(uuidString: String(requestIdentifier.dropFirst(Self.prefix.count))),
              requestIdentifier == Self.identifier(for: id) else { return }
        previewSound?.stop()
        newReminderIDs.remove(id)
        if let reminder = store.reminders.first(where: { $0.id == id }) {
            store.acknowledge(reminder)
        }
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
    }

    private func queue(reminders: [Reminder], sound: ReminderSound, requestPermission: Bool) {
        let previous = schedulingTask
        previous?.cancel()
        schedulingTask = Task { [weak self] in
            // Wait for an in-flight add before removing stale requests from a newer snapshot.
            await previous?.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.reschedule(reminders: reminders, sound: sound,
                                  requestPermission: requestPermission || !self.newReminderIDs.isEmpty)
        }
    }

    private func reschedule(reminders: [Reminder], sound: ReminderSound, requestPermission: Bool) async {
        var permission = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        errorMessage = nil
        if permission.authorizationStatus == .notDetermined && requestPermission {
            isRequestingPermission = true
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                errorMessage = "Couldn't enable reminder notifications: \(error.localizedDescription)"
            }
            isRequestingPermission = false
            permission = await center.notificationSettings()
        }
        guard !Task.isCancelled else { return }
        authorizationStatus = permission.authorizationStatus
        if authorizationStatus == .notDetermined {
            statusMessage = "Enable alerts and sounds for timed reminders."
        } else if authorizationStatus == .denied {
            statusMessage = "Allow FlipClock in System Settings › Notifications."
        } else if permission.soundSetting != .enabled {
            statusMessage = "Sounds are off in System Settings › Notifications."
        } else if permission.alertSetting != .enabled {
            statusMessage = "Alerts are off in System Settings › Notifications."
        } else {
            statusMessage = "Alerts play at each reminder’s scheduled time."
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let now = Date()
        let requests = reminders.compactMap { reminder -> (Reminder, UNNotificationRequest)? in
            guard let request = Self.request(for: reminder, sound: sound, now: now,
                                             notifyIfOverdue: newReminderIDs.contains(reminder.id)) else { return nil }
            return (reminder, request)
        }
        let activeIDs = Set(reminders.filter { !$0.isAcknowledged }.map { Self.identifier(for: $0.id) })
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending
            .filter { $0.identifier.hasPrefix(Self.prefix) && !activeIDs.contains($0.identifier) }
            .map(\.identifier))
        let delivered = await center.deliveredNotifications()
        guard !Task.isCancelled else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.prefix) && !activeIDs.contains($0) })
        for (reminder, request) in requests {
            guard !Task.isCancelled else { return }
            do {
                try await center.add(request)
                newReminderIDs.remove(reminder.id)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "A reminder alert couldn't be scheduled: \(error.localizedDescription)"
            }
        }
    }

    nonisolated static func identifier(for id: UUID) -> String {
        "\(prefix)\(id.uuidString)"
    }

    nonisolated static func request(for reminder: Reminder, sound: ReminderSound, now: Date = Date(),
                                   notifyIfOverdue: Bool = false) -> UNNotificationRequest? {
        guard !reminder.isAcknowledged, reminder.date > now || notifyIfOverdue else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.subtitle = reminder.date.formatted(date: .abbreviated, time: .shortened)
        content.body = reminder.title
        content.sound = sound.notificationSound
        content.threadIdentifier = "FlipClock-reminders"
        content.categoryIdentifier = category.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger: UNNotificationTrigger = reminder.date > now
            ? UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            : UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        return UNNotificationRequest(identifier: identifier(for: reminder.id), content: content, trigger: trigger)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor [weak self] in
            completionHandler(self?.presentationOptions(for: notification.request.identifier) ?? [])
        }
    }

    func presentationOptions(for identifier: String, now: Date = Date()) -> UNNotificationPresentationOptions {
        guard let reminder = store.reminders.first(where: { Self.identifier(for: $0.id) == identifier }),
              !reminder.isAcknowledged,
              // Calendar notification triggers have whole-second precision.
              floor(reminder.date.timeIntervalSince1970) <= now.timeIntervalSince1970 else { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.handleResponse(actionIdentifier: response.actionIdentifier,
                                requestIdentifier: response.notification.request.identifier)
            completionHandler()
        }
    }
}
