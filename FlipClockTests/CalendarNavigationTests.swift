import XCTest
@testable import FlipClock

final class CalendarNavigationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMonthAndYearPickerNavigation() throws {
        var navigation = CalendarNavigation(date: date(2026, 10, 18), calendar: calendar)
        navigation.page(by: 1)
        XCTAssertEqual(navigation.displayedMonth, date(2026, 11, 1))
        XCTAssertEqual(navigation.selectedDate, date(2026, 11, 18))

        navigation.showLargerRange()
        XCTAssertEqual(navigation.level, .months)
        XCTAssertEqual(navigation.months.count, 12)
        navigation.page(by: 1)
        XCTAssertEqual(navigation.year, 2027)

        navigation.showLargerRange()
        XCTAssertEqual(navigation.level, .years)
        let firstPage = navigation.yearPage
        navigation.page(by: 1)
        XCTAssertEqual(navigation.yearPage.lowerBound, firstPage.upperBound + 1)
        navigation.page(by: -1)
        XCTAssertEqual(navigation.yearPage, firstPage)

        navigation.chooseYear(2000)
        XCTAssertEqual(navigation.level, .months)
        XCTAssertEqual(navigation.year, 2000)
        let february = try XCTUnwrap(navigation.months.first { calendar.component(.month, from: $0) == 2 })
        navigation.chooseMonth(february)
        XCTAssertEqual(navigation.level, .days)
        XCTAssertEqual(navigation.displayedMonth, date(2000, 2, 1))
        XCTAssertEqual(navigation.weeks.flatMap { $0 }.compactMap { $0 }.count, 29)
    }

    func testCalendarRowsFitTheMonthAndRespectFirstWeekday() {
        var navigation = CalendarNavigation(date: date(2024, 1, 31), calendar: calendar)
        navigation.page(by: 1)
        XCTAssertEqual(navigation.selectedDate, date(2024, 2, 29))
        XCTAssertEqual(navigation.weeks.count, 5)
        XCTAssertTrue(navigation.weeks.allSatisfy { $0.count == 7 })
        XCTAssertNil(navigation.weeks[0][2])
        XCTAssertEqual(navigation.weeks[0][3], date(2024, 2, 1))

        let fourWeeks = CalendarNavigation(date: date(2021, 2, 1), calendar: calendar)
        XCTAssertEqual(fourWeeks.weeks.count, 4, "No empty sixth week should be reserved")
        let sixWeeks = CalendarNavigation(date: date(2026, 3, 1), calendar: calendar)
        XCTAssertEqual(sixWeeks.weeks.count, 6)
    }

    func testBackingOutMovesOneLevelThenReturnsToToday() {
        let today = date(2026, 10, 18)
        var navigation = CalendarNavigation(date: date(2000, 2, 29), calendar: calendar)
        navigation.showLargerRange()
        navigation.showLargerRange()
        navigation.page(by: 1)
        let browsedMonth = navigation.displayedMonth

        navigation.showSmallerRange(today: today)
        XCTAssertEqual(navigation.level, .months)
        XCTAssertEqual(navigation.displayedMonth, browsedMonth)
        XCTAssertEqual(navigation.months.count, 12)

        navigation.showSmallerRange(today: today)
        XCTAssertEqual(navigation.level, .days)
        XCTAssertEqual(navigation.displayedMonth, date(2026, 10, 1))
        XCTAssertEqual(navigation.selectedDate, today)
        XCTAssertEqual(navigation.calendar, calendar)

        navigation.selectedDate = date(2026, 10, 20)
        navigation.showSmallerRange(today: today)
        XCTAssertEqual(navigation.selectedDate, date(2026, 10, 20), "Empty-space clicks in the day view leave selection alone")
    }

    func testYearNavigationStopsAtSupportedBounds() {
        var first = CalendarNavigation(date: date(1, 1, 1), calendar: calendar)
        XCTAssertNil(first.pageTarget(by: -1))
        first.showLargerRange()
        first.showLargerRange()
        XCTAssertEqual(first.yearPage, 1...12)
        XCTAssertNil(first.pageTarget(by: -1))
        first.chooseYear(0)
        XCTAssertEqual(first.year, 1)

        var last = CalendarNavigation(date: date(9999, 12, 1), calendar: calendar)
        XCTAssertNil(last.pageTarget(by: 1))
        last.showLargerRange()
        last.showLargerRange()
        XCTAssertEqual(last.yearPage.upperBound, 9999)
        XCTAssertNil(last.pageTarget(by: 1))

        var partialPage = CalendarNavigation(date: date(9990, 1, 1), calendar: calendar)
        partialPage.showLargerRange()
        partialPage.showLargerRange()
        partialPage.page(by: 1)
        XCTAssertEqual(partialPage.yearPage, 9997...9999)
    }
}
