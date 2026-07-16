import SwiftUI

/// "Thursday, July 16" (or "Thursday, July 16, 2026" with `showYear`) —
/// weekday and date shown above the clock/calendar in the popover, and
/// optionally above the desktop overlay clock.
struct DateHeaderView: View {
    let date: Date
    var showYear: Bool = false
    var fontSize: CGFloat = 15

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let formatterWithYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    var body: some View {
        Text((showYear ? Self.formatterWithYear : Self.formatter).string(from: date))
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.primary)
    }
}
