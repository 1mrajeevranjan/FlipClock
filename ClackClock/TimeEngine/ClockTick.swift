import Foundation

struct ClockTick: Equatable {
    let date: Date
    let hour12: Int
    let hour24: Int
    let minute: Int
    let second: Int
    let isPM: Bool

    static func now(calendar: Calendar = .current) -> ClockTick {
        at(date: Date(), calendar: calendar)
    }

    /// Reuses an already-captured `Date` (e.g. the primary clock's shared
    /// tick) rather than calling `Date()` again — this is what lets a
    /// second-timezone clock stay in exact lockstep with the primary one
    /// instead of drifting a few milliseconds apart.
    static func at(date: Date, calendar: Calendar) -> ClockTick {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour24 = comps.hour ?? 0
        let hour12Raw = hour24 % 12
        return ClockTick(
            date: date,
            hour12: hour12Raw == 0 ? 12 : hour12Raw,
            hour24: hour24,
            minute: comps.minute ?? 0,
            second: comps.second ?? 0,
            isPM: hour24 >= 12
        )
    }

    static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    /// Hour digits for the given display format — 12-hour (1-12) or
    /// 24-hour (00-23).
    func hourDigits(format: TimeFormat) -> (tens: Int, ones: Int) {
        let hour = format == .twelveHour ? hour12 : hour24
        return (hour / 10, hour % 10)
    }

    var digits: [Int] {
        [hour12 / 10, hour12 % 10, minute / 10, minute % 10, second / 10, second % 10]
    }
}
