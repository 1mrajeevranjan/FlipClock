import XCTest
import SwiftUI
@testable import FlipClock

/// Presses real SwiftUI controls through the in-process accessibility tree —
/// the same elements VoiceOver drives — so buttons are exercised end to end
/// (label → action → model) without needing Screen Recording or Accessibility
/// permission for an external UI-test runner.
@MainActor
final class UIControlsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var store: ReminderStore!

    override func setUp() async throws {
        defaults = isolatedDefaults()
        settings = AppSettings(defaults: defaults)
        store = ReminderStore(defaults: defaults)
    }

    // MARK: Timer

    func testTimerStartPauseResumeReset() throws {
        let timer = CountdownTimer(playCompletionSound: {})
        let ui = HostedView(CountdownTimerView(timerModel: timer, settings: settings))

        try ui.press("Start Timer")
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 300)
        XCTAssertTrue(ui.has("Counting down"))

        try ui.press("Pause")
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(ui.has("Paused"))

        try ui.press("Resume")
        XCTAssertTrue(timer.isRunning)

        try ui.press("Reset")
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertTrue(ui.has("Start Timer"), "Reset returns to the duration picker")
    }

    func testTimerStartIsDisabledAtZeroAndWheelsAdjustWithinRange() throws {
        let timer = CountdownTimer(playCompletionSound: {})
        timer.inputMinutes = 0
        let ui = HostedView(CountdownTimerView(timerModel: timer, settings: settings))
        XCTAssertFalse(try ui.element("Start Timer").isEnabled)

        try ui.element("sec").increment()
        ui.settle()
        XCTAssertEqual(timer.inputSeconds, 1)
        XCTAssertTrue(try ui.element("Start Timer").isEnabled)

        try ui.element("hours").decrement()
        ui.settle()
        XCTAssertEqual(timer.inputHours, 0, "Clamped at the bottom of the reel")
        timer.inputMinutes = 59
        ui.settle()
        try ui.element("min").increment()
        ui.settle()
        XCTAssertEqual(timer.inputMinutes, 59, "Clamped at the top of the reel")
    }

    func testFinishedTimerRingsOnceAndDoneReturnsToPicker() throws {
        var rings = 0
        let timer = CountdownTimer(playCompletionSound: { rings += 1 })
        timer.inputMinutes = 0
        timer.inputSeconds = 1
        let ui = HostedView(CountdownTimerView(timerModel: timer, settings: settings))
        try ui.press("Start Timer")
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        ui.settle()
        XCTAssertTrue(timer.isFinished)
        XCTAssertEqual(rings, 1)
        XCTAssertTrue(ui.has("Time’s up"))

        try ui.press("Done")
        XCTAssertFalse(timer.isFinished)
        XCTAssertTrue(ui.has("Start Timer"))
        XCTAssertEqual(rings, 1)
    }

    // MARK: Stopwatch

    func testStopwatchStartPauseResumeReset() throws {
        let stopwatch = Stopwatch()
        let ui = HostedView(StopwatchView(stopwatch: stopwatch, settings: settings))
        XCTAssertFalse(try ui.element("Reset").isEnabled, "Nothing to reset yet")

        try ui.press("Start")
        XCTAssertTrue(stopwatch.isRunning)
        XCTAssertTrue(try ui.element("Reset").isEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        try ui.press("Pause")
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertTrue(stopwatch.centiseconds > 0 || stopwatch.elapsedSeconds > 0)
        XCTAssertTrue(ui.has("Resume"))

        try ui.press("Resume")
        XCTAssertTrue(stopwatch.isRunning)

        try ui.press("Reset")
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertEqual(stopwatch.elapsedSeconds, 0)
        XCTAssertEqual(stopwatch.centiseconds, 0)
        XCTAssertTrue(ui.has("Start"))
    }

    // MARK: Popover

    private func popover(date: Date = Date()) -> (HostedView<PopoverClockView>, PopoverPresentation) {
        let timeProvider = TimeProvider()
        let timer = CountdownTimer(playCompletionSound: {})
        let stopwatch = Stopwatch()
        let presentation = PopoverPresentation(timeProvider: timeProvider, timerModel: timer, stopwatch: stopwatch, date: date)
        presentation.setPresented(true, timeProvider: timeProvider, date: date)
        let view = PopoverClockView(timeProvider: timeProvider, settings: settings, reminderStore: store,
                                    timerModel: timer, stopwatch: stopwatch, presentation: presentation)
        return (HostedView(view), presentation)
    }

    func testPopoverTabsSwitchTools() throws {
        let (ui, presentation) = popover()
        try ui.press("Timer")
        XCTAssertEqual(presentation.selectedTab, .timer)
        XCTAssertTrue(ui.has("Start Timer"))

        try ui.press("Stopwatch")
        XCTAssertEqual(presentation.selectedTab, .stopwatch)
        XCTAssertTrue(ui.has("Ready when you are"))

        try ui.press("Calendar")
        XCTAssertEqual(presentation.selectedTab, .calendar)
        XCTAssertTrue(ui.has("Add Reminder"))
    }

    func testCalendarPagesMonthsAndDrillsThroughMonthsAndYears() throws {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let (ui, presentation) = popover(date: date)

        try ui.press("Next month")
        XCTAssertEqual(calendar.component(.month, from: presentation.calendarNavigation.displayedMonth), 11)
        try ui.press("Previous month")
        try ui.press("Previous month")
        XCTAssertEqual(calendar.component(.month, from: presentation.calendarNavigation.displayedMonth), 9)

        let monthTitle = presentation.calendarNavigation.displayedMonth.formatted(.dateTime.month(.wide).year())
        try ui.press(monthTitle)
        XCTAssertEqual(presentation.calendarNavigation.level, .months)
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        try ui.press(march.formatted(.dateTime.month(.wide).year()))
        XCTAssertEqual(presentation.calendarNavigation.level, .days)
        XCTAssertEqual(calendar.component(.month, from: presentation.calendarNavigation.displayedMonth), 3)

        try ui.press(march.formatted(.dateTime.month(.wide).year()))
        try ui.press("2026")
        XCTAssertEqual(presentation.calendarNavigation.level, .years)
        try ui.press("Next 12 years")
        try ui.press("2031")
        XCTAssertEqual(presentation.calendarNavigation.level, .months)
        XCTAssertEqual(presentation.calendarNavigation.year, 2031)
    }

    func testSelectingADayThenAddingAReminderSavesIt() throws {
        let calendar = Calendar.current
        let today = Date()
        let (ui, presentation) = popover(date: today)
        let target = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        if !calendar.isDate(target, equalTo: today, toGranularity: .month) { try ui.press("Next month") }

        try ui.pressFirst { $0.role == "AXButton" && $0.label.hasPrefix(target.formatted(date: .complete, time: .omitted)) }
        XCTAssertTrue(calendar.isDate(presentation.calendarNavigation.selectedDate, inSameDayAs: target))

        try ui.press("Add Reminder")
        XCTAssertTrue(ui.has("New Reminder"))
        try ui.press("Cancel")
        XCTAssertFalse(ui.has("New Reminder"))
        XCTAssertTrue(store.reminders.isEmpty)

        try ui.press("Add Reminder")
        XCTAssertFalse(try ui.element("Add Reminder").isEnabled, "Saving needs a title")
        try ui.type("Water the plants", intoFieldWithPlaceholder: "What would you like to remember?")
        try ui.press("Add Reminder")
        XCTAssertEqual(store.reminders.map(\.title), ["Water the plants"])
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(store.reminders.first).date, inSameDayAs: target))
        XCTAssertFalse(ui.has("New Reminder"), "The form closes after saving")
    }

    func testDueTodayBannerAcknowledgesAReminder() throws {
        store.add(title: "Stretch", date: Date())
        let (ui, _) = popover()
        try ui.press("Acknowledge Stretch")
        XCTAssertEqual(store.reminders.first?.isAcknowledged, true)
        XCTAssertFalse(ui.has("Due Today"))
    }

    // MARK: Settings

    private func settingsUI() -> HostedView<some View> {
        let notifications = ReminderNotifications(store: store, settings: settings)
        return HostedView(SettingsView(reminderNotifications: notifications).environmentObject(settings))
    }

    func testSettingsGeneralControls() throws {
        let ui = settingsUI()
        let overlay = settings.showDesktopOverlay
        try ui.press("Desktop clock")
        XCTAssertEqual(settings.showDesktopOverlay, !overlay)
        XCTAssertTrue(try ui.element("Preview notification sound").isEnabled,
                      "The Default sound (system alert) can be previewed too")
    }

    func testSettingsAppearanceControls() throws {
        let ui = settingsUI()
        try ui.press("Appearance")
        try ui.press("Dark")
        XCTAssertEqual(settings.theme, .dark)
        try ui.press("Light")
        XCTAssertEqual(settings.theme, .light)
        for style in MeridiemStyle.allCases {
            try ui.press(style.label)
            XCTAssertEqual(settings.meridiemStyle, style)
        }
    }

    func testSettingsDesktopClockControls() throws {
        let ui = settingsUI()
        try ui.press("Desktop Clock")
        for size in OverlaySize.allCases {
            try ui.press(size.label)
            XCTAssertEqual(settings.overlaySize, size)
        }
        for format in TimeFormat.allCases {
            try ui.press(format.label)
            XCTAssertEqual(settings.timeFormat, format)
        }
        let showDate = settings.showDateOnOverlay
        try ui.press("Show date")
        XCTAssertEqual(settings.showDateOnOverlay, !showDate)
        for style in WidgetColorStyle.allCases {
            try ui.press(style.label)
            XCTAssertEqual(settings.widgetColorStyle, style)
        }

        settings.fillScreen = false
        ui.settle()
        try ui.press("Float across screen")
        XCTAssertTrue(settings.floatAcrossScreen)
        try ui.press("Fill screen")
        XCTAssertTrue(settings.fillScreen)
        XCTAssertFalse(settings.floatAcrossScreen, "Fill screen turns floating off")
        XCTAssertFalse(try ui.element("Float across screen").isEnabled)
    }

    func testSettingsWorldClockCardControls() throws {
        settings.addWorldClock(timezoneID: "Asia/Tokyo")
        let ui = settingsUI()
        try ui.press("World Clocks")
        XCTAssertTrue(ui.has("1 of \(WorldClock.maxCount) clocks"))

        for display in WorldClockDisplay.allCases {
            try ui.press(display.label)
            XCTAssertEqual(settings.worldClocks.first?.display, display)
        }
        try ui.type("HQ", intoFieldWithPlaceholder: "Tokyo")
        XCTAssertEqual(settings.worldClocks.first?.customLabel, "HQ")

        try ui.press("Remove HQ clock")
        XCTAssertTrue(settings.worldClocks.isEmpty)
        XCTAssertTrue(ui.has("A world of time"))
    }

    func testSettingsAddClockDisabledAtLimit() throws {
        for _ in 0..<WorldClock.maxCount { settings.addWorldClock(timezoneID: "UTC") }
        let ui = settingsUI()
        try ui.press("World Clocks")
        XCTAssertFalse(try ui.element("Add Clock").isEnabled)
    }
}

// MARK: - Harness

@MainActor
final class HostedView<Content: View> {
    let window: NSWindow
    let hosting: NSHostingView<Content>

    init(_ content: Content, size: NSSize = NSSize(width: 720, height: 1000)) {
        // What VoiceOver flips on; SwiftUI only vends its tree to an assistive client.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        hosting = NSHostingView(rootView: content)
        window = KeyableWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        // SwiftUI only builds its accessibility tree for a window that's on screen.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        settle()
    }

    deinit {
        MainActor.assumeIsolated { window.orderOut(nil) }
    }

    func settle() {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
    }

    func elements() -> [AXNode] {
        var result: [AXNode] = []
        func walk(_ node: AXNode, depth: Int) {
            guard depth < 60 else { return }
            result.append(node)
            node.children.forEach { walk($0, depth: depth + 1) }
        }
        // SwiftUI materialises its accessibility nodes lazily; a hit test wakes the tree.
        _ = hosting.accessibilityHitTest(window.convertPoint(toScreen: NSPoint(x: hosting.bounds.midX, y: hosting.bounds.midY)))
        walk(AXNode(hosting), depth: 0)
        return result
    }

    func dump() -> String {
        elements().map { "\($0.role) | \($0.label) | \($0.title) | enabled=\($0.isEnabled)" }.joined(separator: "\n")
    }

    func element(where predicate: (AXNode) -> Bool, description: String,
                 file: StaticString = #filePath, line: UInt = #line) throws -> AXNode {
        try XCTUnwrap(elements().first(where: predicate), "No accessibility element \(description).\n\(dump())", file: file, line: line)
    }

    func element(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> AXNode {
        try element(where: { $0.label == label || $0.title == label }, description: "labelled “\(label)”", file: file, line: line)
    }

    func has(_ label: String) -> Bool {
        elements().contains { $0.label == label || $0.title == label || ($0.value as? String) == label }
    }

    func press(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try press(element(label, file: file, line: line), name: label, file: file, line: line)
    }

    func pressFirst(where predicate: (AXNode) -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let target = try element(where: predicate, description: "matching predicate", file: file, line: line)
        try press(target, name: target.label, file: file, line: line)
    }

    private func press(_ target: AXNode, name: String, file: StaticString, line: UInt) throws {
        XCTAssertTrue(target.isEnabled, "“\(name)” is disabled", file: file, line: line)
        let accepted = target.press()
        // AppKit's segmented-control segments act on the press but report `false`;
        // callers assert the resulting state for those instead.
        if target.role == "AXButton" || target.role == "AXCheckBox" {
            XCTAssertTrue(accepted, "“\(name)” didn't accept a press", file: file, line: line)
        }
        settle()
    }

    /// Types like a keyboard would — through the field editor — because setting a
    /// SwiftUI TextField's accessibility value doesn't reach its binding.
    func type(_ text: String, intoFieldWithPlaceholder placeholder: String,
              file: StaticString = #filePath, line: UInt = #line) throws {
        func fields(in view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        let field = try XCTUnwrap(fields(in: hosting).first { $0.placeholderString == placeholder },
                                  "No text field with placeholder “\(placeholder)”", file: file, line: line)
        XCTAssertTrue(window.makeFirstResponder(field), file: file, line: line)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, file: file, line: line)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settle()
    }
}

/// Lets an off-screen test window hold a first responder, so text fields can be typed into.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// SwiftUI's accessibility nodes implement AppKit's accessibility methods without
/// formally conforming to `NSAccessibilityProtocol`, so they're driven dynamically.
struct AXNode {
    let object: AnyObject
    init(_ object: AnyObject) { self.object = object }

    var role: String { (object.accessibilityRole?() ?? nil)?.rawValue ?? "?" }
    var label: String { (object.accessibilityLabel?() ?? nil) ?? "" }
    var title: String { (object.accessibilityTitle?() ?? nil) ?? "" }
    var value: Any? { object.accessibilityValue?() ?? nil }
    var isEnabled: Bool { object.isAccessibilityEnabled?() ?? false }
    var children: [AXNode] { ((object.accessibilityChildren?() ?? nil) ?? []).map { AXNode($0 as AnyObject) } }
    func press() -> Bool { object.accessibilityPerformPress?() ?? false }
    func increment() { _ = object.accessibilityPerformIncrement?() }
    func decrement() { _ = object.accessibilityPerformDecrement?() }
}

func isolatedDefaults() -> UserDefaults {
    let suite = "UIControlsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
