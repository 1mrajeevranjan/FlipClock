import XCTest
import UserNotifications
@testable import FlipClock

final class ReminderNotificationsTests: XCTestCase {
    @MainActor
    func testForegroundSoundRequiresAnExistingUnacknowledgedDueReminder() throws {
        let suite = "ReminderPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReminderStore(defaults: defaults)
        let notifications = ReminderNotifications(store: store, settings: AppSettings(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000.25)
        let unknownID = ReminderNotifications.identifier(for: UUID())
        XCTAssertTrue(notifications.presentationOptions(for: unknownID, now: now).isEmpty)

        store.add(title: "Later", date: now.addingTimeInterval(60))
        let futureID = ReminderNotifications.identifier(for: store.reminders[0].id)
        XCTAssertTrue(notifications.presentationOptions(for: futureID, now: now).isEmpty)

        // Native calendar triggers round to a whole second.
        store.add(title: "Due", date: now.addingTimeInterval(0.5))
        let due = store.reminders[1]
        let dueID = ReminderNotifications.identifier(for: due.id)
        XCTAssertEqual(notifications.presentationOptions(for: dueID, now: now), [.banner, .list])
        store.acknowledge(due)
        XCTAssertTrue(notifications.presentationOptions(for: dueID, now: now).isEmpty)
        store.remove(due)
        XCTAssertTrue(notifications.presentationOptions(for: dueID, now: now).isEmpty)
    }

    func testAlertHasStableIdentityContentAndExactDeliveryDate() throws {
        let now = Date()
        let due = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 120)
        let reminder = Reminder(date: due, title: "Take a break")
        let request = try XCTUnwrap(ReminderNotifications.request(for: reminder, now: now))
        XCTAssertEqual(request.identifier, ReminderNotifications.identifier(for: reminder.id))
        XCTAssertEqual(request.content.body, reminder.title)
        XCTAssertNil(request.content.sound, "The app's looping alarm is the sound; the alert itself stays silent")
        XCTAssertEqual(request.content.categoryIdentifier, ReminderNotifications.category.identifier)
        XCTAssertEqual(ReminderNotifications.category.actions.map(\.identifier), [ReminderNotifications.dismissActionIdentifier])
        XCTAssertEqual(ReminderNotifications.category.actions.first?.title, "Dismiss")
        XCTAssertTrue(ReminderNotifications.category.options.contains(.customDismissAction))
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.nextTriggerDate(), due)
    }

    func testAcknowledgedAndPastRemindersDoNotProduceNewAlerts() {
        let now = Date()
        XCTAssertNil(ReminderNotifications.request(for: Reminder(date: now.addingTimeInterval(-1), title: "Old"),
                                                   now: now))
        XCTAssertNil(ReminderNotifications.request(for: Reminder(date: now.addingTimeInterval(60), title: "Done", isAcknowledged: true),
                                                   now: now))
    }

    @MainActor
    func testDismissRemovesOnlyMatchingReminderAndPersistsAcrossRelaunch() throws {
        let suite = "ReminderNotificationDismissTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReminderStore(defaults: defaults)
        store.add(title: "First", date: Date())
        store.add(title: "Second", date: Date())
        let first = store.reminders[0]
        let second = store.reminders[1]
        let notifications = ReminderNotifications(store: store, settings: AppSettings(defaults: defaults))
        let requestID = ReminderNotifications.identifier(for: first.id)

        for (action, identifier) in [
            (UNNotificationDefaultActionIdentifier, requestID),
            ("unknown-action", requestID),
            (ReminderNotifications.dismissActionIdentifier, first.id.uuidString),
            (ReminderNotifications.dismissActionIdentifier, "FlipClock-reminder-invalid")
        ] {
            notifications.handleResponse(actionIdentifier: action, requestIdentifier: identifier)
        }
        XCTAssertFalse(store.reminders.contains(where: \.isAcknowledged))

        notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier, requestIdentifier: requestID)
        notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier, requestIdentifier: requestID)
        XCTAssertEqual(store.widgetReminders.map(\.id), [second.id])
        XCTAssertEqual(store.dueTodayUnacknowledged.map(\.id), [second.id])
        XCTAssertEqual(store.reminders.map(\.id), [second.id])
        XCTAssertEqual(ReminderStore(defaults: defaults).reminders.map(\.id), [second.id])

        notifications.handleResponse(actionIdentifier: UNNotificationDismissActionIdentifier,
                                     requestIdentifier: ReminderNotifications.identifier(for: second.id))
        XCTAssertTrue(store.reminders.isEmpty, "Closing the native alert also removes it")
        notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier, requestIdentifier: requestID)
        XCTAssertTrue(store.reminders.isEmpty, "A stale alert must not restore a deleted reminder")
    }

    @MainActor
    func testAlarmRingsWhenDueUntilDismissedAndNeverReplaysOldReminders() throws {
        let suite = "ReminderAlarmTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReminderStore(defaults: defaults)
        let now = Date()
        store.add(title: "Already overdue at launch", date: now.addingTimeInterval(-3600))
        store.add(title: "Stand up", date: now.addingTimeInterval(60))
        let due = store.reminders[1]
        let notifications = ReminderNotifications(store: store, settings: AppSettings(defaults: defaults))
        defer { notifications.stopAlarm() }

        notifications.ringDueReminders(now: now)
        XCTAssertFalse(notifications.isRinging, "Relaunching must not replay reminders that were already past due")

        notifications.ringDueReminders(now: due.date)
        XCTAssertTrue(notifications.isRinging)
        notifications.ringDueReminders(now: due.date.addingTimeInterval(1))
        XCTAssertTrue(notifications.isRinging, "Keeps ringing until the user acts on it")

        notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier,
                                     requestIdentifier: ReminderNotifications.identifier(for: due.id))
        XCTAssertFalse(notifications.isRinging)
        XCTAssertFalse(store.reminders.contains { $0.id == due.id }, "Dismiss removes the reminder")
        notifications.ringDueReminders(now: due.date.addingTimeInterval(2))
        XCTAssertFalse(notifications.isRinging)

        store.add(title: "Elsewhere", date: due.date.addingTimeInterval(60))
        let other = try XCTUnwrap(store.reminders.last)
        notifications.ringDueReminders(now: other.date)
        XCTAssertTrue(notifications.isRinging)
        store.acknowledge(other)
        notifications.ringDueReminders(now: other.date.addingTimeInterval(1))
        XCTAssertFalse(notifications.isRinging, "Acknowledging from the popover or menu bar also silences it")
    }

    func testNewlyCreatedOverdueReminderAlertsWithoutReplayingHistoricalOnes() throws {
        let now = Date()
        let reminder = Reminder(date: now.addingTimeInterval(-30), title: "Due this minute")
        let request = try XCTUnwrap(ReminderNotifications.request(for: reminder, now: now,
                                                                  notifyIfOverdue: true))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 1)
        XCTAssertFalse(trigger.repeats)
        XCTAssertNil(ReminderNotifications.request(for: reminder, now: now))
    }

    func testNativeSoundsAreBundledAndStoredSelectionIsValidated() {
        XCTAssertGreaterThan(ReminderSound.all.count, 1)
        XCTAssertEqual(ReminderSound.byID("Glass.aiff").id, "Glass.aiff")
        for sound in ReminderSound.all where sound != .systemDefault {
            XCTAssertNotNil(Bundle.main.url(forResource: sound.id, withExtension: nil))
        }
        XCTAssertEqual(ReminderSound.byID("../untrusted.aiff"), .systemDefault)
        XCTAssertEqual(ReminderSound.byID("removed-sound.aiff"), .systemDefault)
    }

    func testWidgetSummaryIncludesDayTimeAndReminder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))!
        let reminder = Reminder(date: now.addingTimeInterval(3600), title: "Stretch")
        XCTAssertTrue(reminder.summary(relativeTo: now, calendar: calendar).hasPrefix("Today @ "))
        XCTAssertTrue(reminder.summary(relativeTo: now, calendar: calendar).hasSuffix(" – Stretch"))
        var tomorrow = reminder
        tomorrow.date = calendar.date(byAdding: .day, value: 1, to: reminder.date)!
        XCTAssertTrue(tomorrow.summary(relativeTo: now, calendar: calendar).hasPrefix("Tomorrow @ "))
    }
}
