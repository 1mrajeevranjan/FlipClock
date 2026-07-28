import XCTest
@testable import FlipClock

/// Covers the hot paths that run continuously while the app is alive
/// (once/second time-engine math, per-render digit diffing) and the pure
/// decision functions that gate the app's most expensive operation
/// (`DesktopBackdropCapture`'s screen-capture + Gaussian blur). These don't
/// assert specific wall-clock thresholds (`measure` already fails a test on
/// significant regression against its own baseline) — they exist to catch a
/// future change that makes a per-tick/per-render computation accidentally
/// quadratic or newly allocation-heavy.
final class PerformanceTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal
    }

    // MARK: - Time engine (runs every second the app is running)

    func testClockTickComputationPerformance() {
        let cal = calendar()
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 0, second: 0))!
        measure {
            for i in 0..<10_000 {
                let date = base.addingTimeInterval(TimeInterval(i))
                _ = ClockTick.at(date: date, calendar: cal)
            }
        }
    }

    func testDigitDeltaDiffPerformance() {
        let cal = calendar()
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 0, second: 0))!
        var previous: ClockTick?
        let ticks = (0..<10_000).map { i in
            ClockTick.at(date: base.addingTimeInterval(TimeInterval(i)), calendar: cal)
        }
        measure {
            previous = nil
            for tick in ticks {
                let delta = DigitDelta.diff(from: previous, to: tick)
                previous = tick
                XCTAssertNotNil(delta)
            }
        }
    }

    // MARK: - DesktopBackdropCapture pure gates (drives the single most
    // expensive operation in the app — see architecture.md Phase 6)

    func testShouldCaptureIsTrueOnlyWhenWindowIsActuallyVisible() {
        XCTAssertTrue(DesktopBackdropCapture.shouldCapture(occlusionState: .visible))
        XCTAssertFalse(DesktopBackdropCapture.shouldCapture(occlusionState: []))
    }

    func testRefreshIntervalStretchesOutUnderLowPowerMode() {
        XCTAssertEqual(DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: false), 5.0)
        XCTAssertEqual(DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: true), 15.0)
        XCTAssertGreaterThan(
            DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: true),
            DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: false)
        )
    }

    // MARK: - Reminder persistence under load (JSON encode/decode is the
    // ReminderStore's per-mutation cost — see ReminderStoreTests for
    // correctness; this covers throughput on a large reminder set)

    func testReminderStoreBulkAddPerformance() {
        let suiteName = "PerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReminderStore(defaults: defaults)

        measure {
            for i in 0..<200 {
                store.add(title: "Reminder \(i)", date: Date().addingTimeInterval(TimeInterval(i * 60)))
            }
            for reminder in store.reminders {
                store.remove(reminder)
            }
        }
    }

    // MARK: - AppSettings persistence (every toggle in Settings round-trips
    // through UserDefaults synchronously on the main thread)

    func testAppSettingsPersistenceRoundTripPerformance() {
        let suiteName = "PerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        measure {
            for _ in 0..<500 {
                settings.showDesktopOverlay.toggle()
            }
        }
    }
}
