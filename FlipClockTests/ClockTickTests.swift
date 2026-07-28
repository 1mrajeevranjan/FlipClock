import XCTest
@testable import FlipClock

final class ClockTickTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    func testMidnightIsTwelveAM() {
        let tick = ClockTick.at(date: date(hour: 0, minute: 0, second: 0), calendar: calendar())
        XCTAssertEqual(tick.hour12, 12)
        XCTAssertEqual(tick.hour24, 0)
        XCTAssertFalse(tick.isPM)
    }

    func testNoonIsTwelvePM() {
        let tick = ClockTick.at(date: date(hour: 12, minute: 0, second: 0), calendar: calendar())
        XCTAssertEqual(tick.hour12, 12)
        XCTAssertEqual(tick.hour24, 12)
        XCTAssertTrue(tick.isPM)
    }

    func testOnePMIsHourOneInTwelveHourFormat() {
        let tick = ClockTick.at(date: date(hour: 13, minute: 30, second: 45), calendar: calendar())
        XCTAssertEqual(tick.hour12, 1)
        XCTAssertEqual(tick.hour24, 13)
        XCTAssertTrue(tick.isPM)
        XCTAssertEqual(tick.minute, 30)
        XCTAssertEqual(tick.second, 45)
    }

    func testElevenPMStaysInPM() {
        let tick = ClockTick.at(date: date(hour: 23, minute: 59, second: 59), calendar: calendar())
        XCTAssertEqual(tick.hour12, 11)
        XCTAssertEqual(tick.hour24, 23)
        XCTAssertTrue(tick.isPM)
    }

    func testHourDigitsRespectFormat() {
        let tick = ClockTick.at(date: date(hour: 9, minute: 5, second: 0), calendar: calendar())
        XCTAssertEqual(tick.hourDigits(format: .twelveHour).tens, 0)
        XCTAssertEqual(tick.hourDigits(format: .twelveHour).ones, 9)
        XCTAssertEqual(tick.hourDigits(format: .twentyFourHour).tens, 0)
        XCTAssertEqual(tick.hourDigits(format: .twentyFourHour).ones, 9)
    }

    func testDigitsArraySplitsEachFieldIntoTensAndOnes() {
        let tick = ClockTick.at(date: date(hour: 11, minute: 42, second: 7), calendar: calendar())
        // hour12 for 11 is 11 -> [1,1], minute 42 -> [4,2], second 07 -> [0,7]
        XCTAssertEqual(tick.digits, [1, 1, 4, 2, 0, 7])
    }
}
