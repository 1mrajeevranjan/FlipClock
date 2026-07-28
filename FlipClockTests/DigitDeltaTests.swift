import XCTest
@testable import FlipClock

final class DigitDeltaTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func tick(hour: Int, minute: Int, second: Int) -> ClockTick {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return ClockTick.at(date: calendar.date(from: comps)!, calendar: calendar)
    }

    func testFirstTickMarksEveryPositionChanged() {
        let delta = DigitDelta.diff(from: nil, to: tick(hour: 9, minute: 0, second: 0))
        XCTAssertEqual(delta.changedPositions, Set(0..<6))
        XCTAssertTrue(delta.amPmChanged)
    }

    func testOnlySecondsOnesChangesOnASimpleTick() {
        let old = tick(hour: 9, minute: 0, second: 0)
        let new = tick(hour: 9, minute: 0, second: 1)
        let delta = DigitDelta.diff(from: old, to: new)
        XCTAssertEqual(delta.changedPositions, [5])
        XCTAssertFalse(delta.amPmChanged)
    }

    func testSecondsRolloverCascadesIntoMinutes() {
        // 09:00:59 -> 09:01:00: seconds tens+ones AND minute ones all change.
        let old = tick(hour: 9, minute: 0, second: 59)
        let new = tick(hour: 9, minute: 1, second: 0)
        let delta = DigitDelta.diff(from: old, to: new)
        XCTAssertEqual(delta.changedPositions, [3, 4, 5])
    }

    func testMidnightRolloverCascadesThroughEveryPositionExceptHourTens() {
        // 11:59:59 PM -> 12:00:00 AM: minutes, seconds, AM/PM, and the hour
        // ones digit (1 -> 2) all change — but hour12 goes "11" -> "12",
        // and the TENS digit is "1" in both, so position 0 alone is
        // unchanged. (First caught this by asserting the wrong thing —
        // Set(0..<6) — and getting a real, correct diff back that just
        // didn't match a bad assumption about what "everything" means for
        // a 12-hour clock specifically.)
        let old = tick(hour: 23, minute: 59, second: 59)
        let new = tick(hour: 0, minute: 0, second: 0)
        let delta = DigitDelta.diff(from: old, to: new)
        XCTAssertEqual(delta.changedPositions, [1, 2, 3, 4, 5])
        XCTAssertTrue(delta.amPmChanged)
    }

    func testNoonRolloverFlipsAmPmWithoutChangingHourDigitsInTwelveHourClock() {
        // 11:59:59 AM -> 12:00:00 PM: hour12 stays "12", but AM/PM flips.
        let old = tick(hour: 11, minute: 59, second: 59)
        let new = tick(hour: 12, minute: 0, second: 0)
        let delta = DigitDelta.diff(from: old, to: new)
        XCTAssertTrue(delta.amPmChanged)
        // hour12 digits: 11 -> [1,1], 12 -> [1,2] — ones digit does change here.
        XCTAssertTrue(delta.changedPositions.contains(1))
    }

    func testIdenticalTicksProduceNoChangedPositions() {
        let t = tick(hour: 9, minute: 0, second: 0)
        let delta = DigitDelta.diff(from: t, to: t)
        XCTAssertTrue(delta.changedPositions.isEmpty)
        XCTAssertFalse(delta.amPmChanged)
    }
}
