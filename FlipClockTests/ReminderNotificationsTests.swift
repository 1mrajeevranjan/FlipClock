import XCTest
import UserNotifications
@testable import FlipClock

final class ReminderNotificationsTests: XCTestCase {
    func testAlertHasStableIdentityContentSoundAndExactDeliveryDate() throws {
        let now = Date()
        let due = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 120)
        let reminder = Reminder(date: due, title: "Take a break")
        let request = try XCTUnwrap(ReminderNotifications.request(for: reminder, sound: .systemDefault, now: now))
        XCTAssertEqual(request.identifier, ReminderNotifications.identifier(for: reminder.id))
        XCTAssertEqual(request.content.body, reminder.title)
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(request.content.categoryIdentifier, ReminderNotifications.category.identifier)
        XCTAssertEqual(ReminderNotifications.category.actions.map(\.identifier), [ReminderNotifications.dismissActionIdentifier])
        XCTAssertEqual(ReminderNotifications.category.actions.first?.title, "Dismiss")
        XCTAssertTrue(ReminderNotifications.category.options.contains(.customDismissAction))
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.nextTriggerDate(), due)
        XCTAssertEqual(ReminderNotifications.request(for: reminder, sound: .byID("Glass.aiff"), now: now)?.identifier,
                       request.identifier, "Changing sound replaces the same alert instead of duplicating it")
    }

    func testAcknowledgedAndPastRemindersDoNotProduceNewAlerts() {
        let now = Date()
        XCTAssertNil(ReminderNotifications.request(for: Reminder(date: now.addingTimeInterval(-1), title: "Old"),
                                                   sound: .systemDefault, now: now))
        XCTAssertNil(ReminderNotifications.request(for: Reminder(date: now.addingTimeInterval(60), title: "Done", isAcknowledged: true),
                                                   sound: .systemDefault, now: now))
    }

    @MainActor
    func testDismissAcknowledgesOnlyMatchingReminderAndPersistsAcrossRelaunch() throws {
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
        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.first(where: { $0.id == first.id })?.isAcknowledged, true)
        XCTAssertNil(ReminderNotifications.request(for: reloaded.reminders[0], sound: .systemDefault, notifyIfOverdue: true))

        notifications.handleResponse(actionIdentifier: UNNotificationDismissActionIdentifier,
                                     requestIdentifier: ReminderNotifications.identifier(for: second.id))
        XCTAssertTrue(store.widgetReminders.isEmpty, "Closing the native alert also acknowledges it")
        store.remove(first)
        notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier, requestIdentifier: requestID)
        XCTAssertEqual(store.reminders.count, 1, "A stale alert must not restore a deleted reminder")
    }

    func testNewlyCreatedOverdueReminderAlertsWithoutReplayingHistoricalOnes() throws {
        let now = Date()
        let reminder = Reminder(date: now.addingTimeInterval(-30), title: "Due this minute")
        let request = try XCTUnwrap(ReminderNotifications.request(for: reminder, sound: .systemDefault,
                                                                  now: now, notifyIfOverdue: true))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 1)
        XCTAssertFalse(trigger.repeats)
        XCTAssertNil(ReminderNotifications.request(for: reminder, sound: .systemDefault, now: now))
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
