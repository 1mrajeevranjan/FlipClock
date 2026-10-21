import XCTest
import AppKit
import Combine
@testable import FlipClock

final class InteractionStressTests: XCTestCase {
    @MainActor
    func testEveryFontChoiceAndApplicationIconResolveFromTheBundle() throws {
        WidgetFont.registerAll()
        for font in WidgetFont.bundled {
            let name = try XCTUnwrap(font.postscriptName)
            XCTAssertNotNil(NSFont(name: name, size: 24), "The \(font.label) option must resolve its bundled font")
        }
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        let icon = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertTrue(icon.isValid)
    }

    @MainActor
    func testRapidToolSwitchesAndRepeatedControlsLeaveNoHiddenUpdates() async throws {
        let time = TimeProvider()
        let timer = CountdownTimer(playCompletionSound: {})
        timer.inputMinutes = 1
        let stopwatch = Stopwatch()
        let presentation = PopoverPresentation(timeProvider: time, timerModel: timer, stopwatch: stopwatch)
        defer { timer.reset(); stopwatch.reset() }

        for index in 0..<1_000 {
            presentation.selectedTab = PopoverTab.allCases[index % PopoverTab.allCases.count]
            presentation.setPresented(index % 4 != 0, timeProvider: time)
            switch index % 8 {
            case 0: timer.start(); stopwatch.start()
            case 1: timer.start(); stopwatch.start()
            case 2: timer.pause(); stopwatch.stop()
            case 3: timer.resume(); stopwatch.start()
            case 4: timer.reset(); stopwatch.reset()
            case 5: timer.start(); stopwatch.start()
            case 6: timer.setDisplayActive(false); stopwatch.setDisplayActive(false)
            default: presentation.setPresented(true, timeProvider: time)
            }
            XCTAssertGreaterThanOrEqual(timer.remainingSeconds, 0)
            XCTAssertFalse(timer.isFinished && timer.isRunning)
            XCTAssertGreaterThanOrEqual(stopwatch.elapsedSeconds, 0)
            XCTAssertTrue((0...99).contains(stopwatch.centiseconds))
            if index % 10 == 0 { try await Task.sleep(for: .milliseconds(10)) }
        }

        presentation.selectedTab = .stopwatch
        presentation.setPresented(true, timeProvider: time)
        stopwatch.start()
        try await Task.sleep(for: .milliseconds(120))
        var updates = 0
        let subscription = stopwatch.$centiseconds.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }
        presentation.setPresented(false, timeProvider: time)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(updates, 0, "Rapid switching must not leak a second display timer")
        presentation.setPresented(true, timeProvider: time)
        XCTAssertGreaterThan(updates, 0)
    }

    func testCalendarMonthPagingAcrossFourCenturiesPreservesEveryDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 1800, month: 1, day: 31)))
        var navigation = CalendarNavigation(date: start, calendar: calendar)
        for _ in 0..<(400 * 12) {
            let days = navigation.weeks.flatMap { $0 }.compactMap { $0 }
            let expected = try XCTUnwrap(calendar.range(of: .day, in: .month, for: navigation.displayedMonth))
            XCTAssertEqual(days.count, expected.count)
            XCTAssertEqual(Set(days).count, days.count)
            XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, Array(expected))
            XCTAssertTrue(days.allSatisfy { calendar.isDate($0, equalTo: navigation.displayedMonth, toGranularity: .month) })
            XCTAssertTrue(calendar.isDate(navigation.selectedDate, equalTo: navigation.displayedMonth, toGranularity: .month))
            navigation.page(by: 1)
        }
        XCTAssertEqual(navigation.year, 2200)
        for _ in 0..<(400 * 12) { navigation.page(by: -1) }
        XCTAssertEqual(navigation.displayedMonth, calendar.dateInterval(of: .month, for: start)?.start)
    }

    func testSettingsAndWorldClockChurnPreserveSelectionsAcrossReloads() throws {
        let suite = "InteractionStressTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let zones = ["UTC", "Asia/Kolkata", "America/New_York", "Europe/London", "Pacific/Auckland"]
        for index in 0..<300 {
            settings.theme = AppTheme.allCases[index % AppTheme.allCases.count]
            settings.overlaySize = OverlaySize.allCases[index % OverlaySize.allCases.count]
            settings.timeFormat = TimeFormat.allCases[index % TimeFormat.allCases.count]
            settings.meridiemStyle = MeridiemStyle.allCases[index % MeridiemStyle.allCases.count]
            settings.widgetColorStyle = WidgetColorStyle.allCases[index % WidgetColorStyle.allCases.count]
            settings.widgetFont = WidgetFont.all[index % WidgetFont.all.count]
            settings.reminderSound = ReminderSound.all[index % ReminderSound.all.count]
            settings.showDesktopOverlay = index % 2 == 0
            settings.showDateOnOverlay = index % 3 == 0
            settings.fillScreen = false
            settings.floatAcrossScreen = true
            settings.fillScreen = true
            XCTAssertFalse(settings.floatAcrossScreen)
            settings.addWorldClock(timezoneID: zones[index % zones.count])
            if let clock = settings.worldClocks.first {
                settings.worldClocks[0].display = WorldClockDisplay.allCases[index % WorldClockDisplay.allCases.count]
                settings.worldClocks[0].customLabel = "City \(index) 🌏"
                if index % 3 == 0 { settings.removeWorldClock(id: clock.id) }
            }
            XCTAssertLessThanOrEqual(settings.worldClocks.count, WorldClock.maxCount)
            XCTAssertEqual(Set(settings.worldClocks.map(\.id)).count, settings.worldClocks.count)
            if index % 30 == 0 {
                let reloaded = AppSettings(defaults: defaults)
                XCTAssertEqual(reloaded.worldClocks, settings.worldClocks)
                XCTAssertEqual(reloaded.theme, settings.theme)
                XCTAssertEqual(reloaded.widgetFont, settings.widgetFont)
                XCTAssertEqual(reloaded.reminderSound, settings.reminderSound)
            }
        }
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.timeFormat, settings.timeFormat)
        XCTAssertEqual(reloaded.overlaySize, settings.overlaySize)
        XCTAssertEqual(reloaded.meridiemStyle, settings.meridiemStyle)
        XCTAssertEqual(reloaded.widgetColorStyle, settings.widgetColorStyle)
        XCTAssertEqual(reloaded.showDesktopOverlay, settings.showDesktopOverlay)
        XCTAssertEqual(reloaded.showDateOnOverlay, settings.showDateOnOverlay)
        XCTAssertEqual(reloaded.fillScreen, settings.fillScreen)
        XCTAssertEqual(reloaded.floatAcrossScreen, settings.floatAcrossScreen)
    }

    func testReminderBatchKeepsNotificationIdentityAndAcknowledgmentConsistent() throws {
        let suite = "InteractionStressTests.Reminders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReminderStore(defaults: defaults)
        let now = Date()
        for index in 0..<500 {
            store.add(title: "Reminder \(index) 🗓️", date: now.addingTimeInterval(Double(index + 1) * 60))
        }
        let originals = store.reminders
        var identifiers = Set<String>()
        for (index, reminder) in originals.enumerated() {
            let request = try XCTUnwrap(ReminderNotifications.request(for: reminder, now: now))
            XCTAssertTrue(identifiers.insert(request.identifier).inserted)
            XCTAssertEqual(request.content.body, reminder.title)
            if index % 2 == 0 {
                store.acknowledge(reminder)
                let acknowledged = try XCTUnwrap(store.reminders.first { $0.id == reminder.id })
                XCTAssertNil(ReminderNotifications.request(for: acknowledged, now: now))
                XCTAssertFalse(store.reminders(on: reminder.date).contains { $0.id == reminder.id })
            } else {
                store.remove(reminder)
            }
        }
        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.count, 250)
        XCTAssertTrue(reloaded.reminders.allSatisfy(\.isAcknowledged))
        XCTAssertTrue(reloaded.widgetReminders.isEmpty)
        XCTAssertTrue(reloaded.reminders(on: now).isEmpty)
    }

    @MainActor
    func testWheelArrowKeysAlwaysReachTheFocusedComponent() throws {
        let view = WheelScrollCaptureView(frame: .zero)
        var steps: [Int] = []
        view.onStep = { steps.append($0) }
        XCTAssertTrue(view.acceptsFirstResponder)
        for index in 0..<1_000 {
            let up = index % 2 == 0
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil,
                                                      characters: up ? "\u{F700}" : "\u{F701}",
                                                      charactersIgnoringModifiers: up ? "\u{F700}" : "\u{F701}",
                                                      isARepeat: false, keyCode: up ? 126 : 125))
            view.keyDown(with: event)
        }
        XCTAssertEqual(steps.count, 1_000)
        XCTAssertEqual(steps.reduce(0, +), 0)
        XCTAssertEqual(Array(steps.prefix(4)), [1, -1, 1, -1])
    }

    @MainActor
    func testEveryMoreMenuCommandIsEnabledAndImplemented() throws {
        let menu = StatusItemController.makeMoreMenu(target: NSObject())
        let commands = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(commands.count, 7)
        for command in commands {
            let action = try XCTUnwrap(command.action, "\(command.title) has no action — a dead menu item")
            XCTAssertTrue(StatusItemController.instancesRespond(to: action), "\(command.title) must have an implemented action")
            XCTAssertTrue(command.isEnabled)
        }
        for link in [StatusItemController.Links.website, StatusItemController.Links.support, StatusItemController.Links.moreApps] {
            XCTAssertEqual(link.scheme, "https")
        }
    }
}
