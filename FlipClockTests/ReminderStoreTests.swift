import XCTest
@testable import FlipClock

final class ReminderStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReminderStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStartsEmpty() {
        let store = ReminderStore(defaults: defaults)
        XCTAssertTrue(store.reminders.isEmpty)
    }

    func testAddAppendsAndPersists() {
        let store = ReminderStore(defaults: defaults)
        store.add(title: "Buy milk", date: Date())
        XCTAssertEqual(store.reminders.count, 1)
        XCTAssertEqual(store.reminders.first?.title, "Buy milk")
        XCTAssertFalse(store.reminders.first!.isAcknowledged)

        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.count, 1)
        XCTAssertEqual(reloaded.reminders.first?.title, "Buy milk")
    }

    func testRemoveDeletesOnlyTheMatchingReminder() {
        let store = ReminderStore(defaults: defaults)
        store.add(title: "A", date: Date())
        store.add(title: "B", date: Date())
        let toRemove = store.reminders.first { $0.title == "A" }!

        store.remove(toRemove)

        XCTAssertEqual(store.reminders.count, 1)
        XCTAssertEqual(store.reminders.first?.title, "B")
    }

    func testAcknowledgeFlipsOnlyTheTargetedReminder() {
        let store = ReminderStore(defaults: defaults)
        store.add(title: "A", date: Date())
        store.add(title: "B", date: Date())
        let target = store.reminders.first { $0.title == "A" }!

        store.acknowledge(target)

        let a = store.reminders.first { $0.title == "A" }!
        let b = store.reminders.first { $0.title == "B" }!
        XCTAssertTrue(a.isAcknowledged)
        XCTAssertFalse(b.isAcknowledged)
    }

    func testAcknowledgingAnAlreadyRemovedReminderIsANoOpNotACrash() {
        let store = ReminderStore(defaults: defaults)
        store.add(title: "A", date: Date())
        let ghost = store.reminders.first!
        store.remove(ghost)

        store.acknowledge(ghost) // must not crash, must not resurrect it

        XCTAssertTrue(store.reminders.isEmpty)
    }

    func testDueTodayUnacknowledgedExcludesAcknowledgedAndFutureReminders() {
        let store = ReminderStore(defaults: defaults)
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        store.add(title: "today unack", date: today)
        store.add(title: "tomorrow", date: tomorrow)
        let ackToday = store.reminders.first { $0.title == "today unack" }!
        store.add(title: "today ack", date: today)
        let willAck = store.reminders.first { $0.title == "today ack" }!
        store.acknowledge(willAck)

        let due = store.dueTodayUnacknowledged
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.id, ackToday.id)
    }

    func testUpcomingWithin24HoursExcludesTodayAndBeyond24Hours() {
        let store = ReminderStore(defaults: defaults)
        let calendar = Calendar.current
        let now = Date()

        // Tomorrow, and by definition at most 24h out: should count as
        // "upcoming". Deliberately start-of-tomorrow rather than "now + 12h",
        // which only lands on tomorrow when the test runs after midday — it
        // failed every morning otherwise, since `upcomingWithin24Hours`
        // excludes today and "now + 12h" is still today before noon.
        let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        store.add(title: "in 12h", date: startOfTomorrow)

        // 48 hours out: too far, should NOT count as "upcoming".
        let in48h = calendar.date(byAdding: .hour, value: 48, to: now)!
        store.add(title: "in 48h", date: in48h)

        // Later today: excluded from "upcoming" — that's dueToday's job,
        // not upcoming's, even though it's within 24 hours.
        store.add(title: "later today", date: now)

        let upcoming = store.upcomingWithin24Hours
        XCTAssertEqual(upcoming.map(\.title), ["in 12h"])
    }

    func testAcknowledgeAllDueTodayAcknowledgesEveryUnacknowledgedTodayReminder() {
        let store = ReminderStore(defaults: defaults)
        let today = Date()
        store.add(title: "one", date: today)
        store.add(title: "two", date: today)

        store.acknowledgeAllDueToday()

        XCTAssertTrue(store.reminders.allSatisfy(\.isAcknowledged))
        XCTAssertTrue(store.dueTodayUnacknowledged.isEmpty)
    }

    func testHasReminderBannerReflectsEitherDueOrUpcoming() {
        let store = ReminderStore(defaults: defaults)
        XCTAssertFalse(store.hasReminderBanner)

        store.add(title: "today", date: Date())
        XCTAssertTrue(store.hasReminderBanner)
    }

    func testLoadingCorruptedPersistedDataFallsBackToEmptyInsteadOfCrashing() {
        defaults.set("not valid json".data(using: .utf8), forKey: "reminders")
        let store = ReminderStore(defaults: defaults)
        XCTAssertTrue(store.reminders.isEmpty)
    }

    // MARK: - Stress

    /// 500 rapid adds followed by 500 rapid removes — the kind of load a
    /// real user would never generate by hand, but a sanity check that
    /// `save()`'s JSON round-trip and `remove`'s linear scan hold up
    /// without corrupting state or throwing under volume.
    func testStressAddAndRemoveManyReminders() {
        let store = ReminderStore(defaults: defaults)
        let count = 500

        for i in 0..<count {
            store.add(title: "Reminder \(i)", date: Date())
        }
        XCTAssertEqual(store.reminders.count, count)

        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.count, count, "persisted count must survive a full JSON round-trip under load")

        for reminder in store.reminders {
            store.remove(reminder)
        }
        XCTAssertTrue(store.reminders.isEmpty)

        let reloadedAfterRemoval = ReminderStore(defaults: defaults)
        XCTAssertTrue(reloadedAfterRemoval.reminders.isEmpty)
    }

    func testStressAcknowledgeAllUnderLoadIsIdempotent() {
        let store = ReminderStore(defaults: defaults)
        for i in 0..<200 {
            store.add(title: "\(i)", date: Date())
        }

        store.acknowledgeAllDueToday()
        store.acknowledgeAllDueToday() // calling twice must not throw or double-toggle

        XCTAssertTrue(store.reminders.allSatisfy(\.isAcknowledged))
    }
}
