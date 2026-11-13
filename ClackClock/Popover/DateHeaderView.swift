import SwiftUI

/// "Thursday, July 16" (or "Thursday, July 16, 2026" with `showYear`) —
/// weekday and date shown above the clock/calendar in the popover, and
/// optionally above the desktop overlay clock.
struct DateHeaderView: View {
    let date: Date
    var showYear: Bool = false

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
            // HIG 9.1: a semantic style (15pt on macOS) rather than a fixed
            // size, so it follows Bold Text and matches system headers.
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}
