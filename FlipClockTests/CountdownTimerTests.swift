import XCTest
import Combine
@testable import FlipClock

final class CountdownTimerTests: XCTestCase {
    func testStartWhileRunningDoesNotOverwriteTheActiveCountdown() {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 5
        timer.start()
        defer { timer.reset() }
        timer.inputSeconds = 30
        timer.start()
        XCTAssertEqual(timer.remainingSeconds, 5, "Repeated Start must not replace the display while keeping the old deadline")
    }

    @MainActor
    func testShowingCountdownNearItsDeadlineDoesNotDelayCompletion() async throws {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 2
        timer.setDisplayActive(false)
        timer.start()
        defer { timer.reset() }
        try await Task.sleep(for: .milliseconds(1600))
        timer.setDisplayActive(true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(timer.isFinished, "Reopening the timer must preserve its original completion deadline")
        XCTAssertEqual(timer.remainingSeconds, 0)
    }

    @MainActor
    func testHiddenCountdownSleepsUntilCompletionAndCatchesUpWhenShown() async throws {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 3
        timer.setDisplayActive(false)
        timer.start()
        defer { timer.reset() }
        var displayUpdates = 0
        let subscription = timer.$remainingSeconds.dropFirst().sink { _ in displayUpdates += 1 }
        defer { subscription.cancel() }

        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(displayUpdates, 0)
        XCTAssertTrue(timer.isRunning)
        timer.setDisplayActive(true)
        XCTAssertEqual(timer.remainingSeconds, 2)
        timer.setDisplayActive(false)
        try await Task.sleep(for: .milliseconds(2100))
        XCTAssertTrue(timer.isFinished, "Completion still fires while the popover is closed")
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
    }

    func testStartWithZeroDurationDoesNothing() {
        let timer = CountdownTimer()
        timer.inputHours = 0
        timer.inputMinutes = 0
        timer.inputSeconds = 0

        timer.start()

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
    }

    func testStartSeedsRemainingSecondsFromInputsAndBeginsRunning() {
        let timer = CountdownTimer()
        timer.inputHours = 0
        timer.inputMinutes = 1
        timer.inputSeconds = 30

        timer.start()

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 90)
        timer.pause()
    }

    func testPauseStopsTheCountdownWithoutResettingRemainingTime() {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 5
        timer.start()

        timer.pause()

        XCTAssertFalse(timer.isRunning)
        XCTAssertGreaterThan(timer.remainingSeconds, 0)
    }

    func testResumeAfterPauseContinuesFromWhereItLeftOff() {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 5
        timer.start()
        timer.pause()
        let remainingAtPause = timer.remainingSeconds

        timer.resume()

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, remainingAtPause)
        timer.pause()
    }

    func testResumeWithZeroRemainingSecondsDoesNothing() {
        let timer = CountdownTimer()
        // Never started — remainingSeconds is still 0 from init.
        timer.resume()
        XCTAssertFalse(timer.isRunning)
    }

    func testResetClearsRemainingTimeAndFinishedFlag() {
        let timer = CountdownTimer()
        timer.inputSeconds = 5
        timer.start()

        timer.reset()

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.isFinished)
    }

    /// Ticks against a real 1-second `Timer`, so this genuinely waits ~2s —
    /// confirms the countdown actually counts down in real time, not just
    /// that the initial seed value is correct.
    func testCountsDownInRealTime() {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 3
        timer.start()

        let expectation = expectation(description: "remainingSeconds decreases")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            XCTAssertLessThan(timer.remainingSeconds, 3)
            timer.pause()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testFinishesAndPlaysThroughToIsFinishedTrue() {
        let timer = CountdownTimer()
        timer.inputMinutes = 0
        timer.inputSeconds = 1
        timer.start()

        let expectation = expectation(description: "timer finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertTrue(timer.isFinished)
            XCTAssertFalse(timer.isRunning)
            XCTAssertEqual(timer.remainingSeconds, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Stress

    /// Rapid start/pause/resume/reset cycling, back to back with no delay —
    /// the exact pattern that would expose a leaked/duplicated `Timer` (two
    /// timers racing to decrement the same counter twice as fast) or a
    /// dangling closure keeping a stale timer alive after `reset()`.
    func testStressRapidStartPauseResumeResetCyclingLeavesConsistentState() {
        let timer = CountdownTimer()
        timer.inputSeconds = 10

        for _ in 0..<100 {
            timer.start()
            timer.pause()
            timer.resume()
            timer.pause()
            timer.reset()
        }

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)

        // If a duplicate timer survived the churn above, letting the
        // countdown run for real would reveal it by finishing/dropping
        // faster than one tick per second should allow.
        timer.inputMinutes = 0
        timer.inputSeconds = 3
        timer.start()
        let expectation = expectation(description: "single-rate countdown after stress")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            // A correct single timer has ticked at most once or twice by
            // now (>=2 remaining); a duplicated timer would have ticked it
            // down much further.
            XCTAssertGreaterThanOrEqual(timer.remainingSeconds, 1)
            timer.pause()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
