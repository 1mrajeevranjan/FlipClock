import Foundation

/// Which of the 6 digit positions (H-tens, H-ones, M-tens, M-ones, S-tens, S-ones)
/// changed between two ticks, plus whether AM/PM flipped. Used so each
/// `SplitFlapDigit` only animates when its own value actually changed.
struct DigitDelta {
    let changedPositions: Set<Int>
    let amPmChanged: Bool

    static func diff(from old: ClockTick?, to new: ClockTick) -> DigitDelta {
        guard let old else {
            return DigitDelta(changedPositions: Set(0..<6), amPmChanged: true)
        }
        let oldDigits = old.digits
        let newDigits = new.digits
        var changed = Set<Int>()
        for i in 0..<6 where oldDigits[i] != newDigits[i] {
            changed.insert(i)
        }
        return DigitDelta(changedPositions: changed, amPmChanged: old.isPM != new.isPM)
    }
}
