import XCTest
@testable import FlipClock

final class StopwatchTests: XCTestCase {
    func testStartsAtZeroAndNotRunning() {
        let stopwatch = Stopwatch()
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertEqual(stopwatch.elapsedSeconds, 0)
        XCTAssertEqual(stopwatch.centiseconds, 0)
    }

    func testStartBeginsRunning() {
        let stopwatch = Stopwatch()
        stopwatch.start()
        XCTAssertTrue(stopwatch.isRunning)
        stopwatch.stop()
    }

    func testStartWhileAlreadyRunningIsANoOp() {
        let stopwatch = Stopwatch()
        stopwatch.start()
        stopwatch.start() // must not reset the start reference / accumulate double
        XCTAssertTrue(stopwatch.isRunning)
        stopwatch.stop()
    }

    func testStopWhileNotRunningIsANoOp() {
        let stopwatch = Stopwatch()
        stopwatch.stop() // must not crash
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertEqual(stopwatch.elapsedSeconds, 0)
    }

    func testResetClearsElapsedTimeAndStopsRunning() {
        let stopwatch = Stopwatch()
        stopwatch.start()
        stopwatch.reset()
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertEqual(stopwatch.elapsedSeconds, 0)
        XCTAssertEqual(stopwatch.centiseconds, 0)
    }

    /// Ticks against the real 30ms timer, so this genuinely waits — confirms
    /// elapsed time actually advances, not just that start() flips a flag.
    func testElapsesInRealTime() {
        let stopwatch = Stopwatch()
        stopwatch.start()

        let expectation = expectation(description: "time elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertGreaterThanOrEqual(stopwatch.elapsedSeconds, 1)
            stopwatch.stop()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testAccumulatesAcrossMultipleStartStopCycles() {
        let stopwatch = Stopwatch()

        let firstRun = expectation(description: "first run")
        stopwatch.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopwatch.stop()
            firstRun.fulfill()
        }
        wait(for: [firstRun], timeout: 3)
        let afterFirstStop = stopwatch.elapsedSeconds + stopwatch.centiseconds

        let secondRun = expectation(description: "second run")
        stopwatch.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopwatch.stop()
            secondRun.fulfill()
        }
        wait(for: [secondRun], timeout: 3)
        let afterSecondStop = stopwatch.elapsedSeconds * 100 + stopwatch.centiseconds

        // Total elapsed after two ~0.5s runs must be strictly more than
        // after just the first — confirms `accumulated` really accumulates
        // instead of being clobbered by the second `start()`.
        XCTAssertGreaterThan(afterSecondStop, afterFirstStop)
    }

    // MARK: - Stress

    /// Rapid start/stop cycling with no delay between calls — the pattern
    /// most likely to expose a leaked `Timer` (guard-clause failing to
    /// invalidate the previous one) or `accumulated` drifting from double
    /// counting.
    func testStressRapidStartStopCyclingLeavesConsistentState() {
        let stopwatch = Stopwatch()

        for _ in 0..<200 {
            stopwatch.start()
            stopwatch.stop()
        }

        XCTAssertFalse(stopwatch.isRunning)

        // A leaked timer from the churn above would keep ticking after this
        // point even though we never call start() again.
        let elapsedRightAfterStress = stopwatch.elapsedSeconds
        let expectation = expectation(description: "no phantom ticking after stress")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(stopwatch.elapsedSeconds, elapsedRightAfterStress, "elapsed time must not change while stopped, even after rapid start/stop churn")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    func testStressManyResetsWhileRunningNeverLeavesNegativeOrRunningState() {
        let stopwatch = Stopwatch()
        for _ in 0..<100 {
            stopwatch.start()
            stopwatch.reset()
            XCTAssertFalse(stopwatch.isRunning)
            XCTAssertGreaterThanOrEqual(stopwatch.elapsedSeconds, 0)
            XCTAssertGreaterThanOrEqual(stopwatch.centiseconds, 0)
        }
    }
}
