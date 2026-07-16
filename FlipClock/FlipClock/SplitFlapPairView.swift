import SwiftUI

/// Two digits side by side (e.g. "HH"), each in its own black leaf module,
/// with a thin gap between the two drums matching the reference clock's
/// twin-module look.
struct SplitFlapPairView: View {
    let tens: Int
    let ones: Int
    let cardSize: CGSize
    var digitSpacing: CGFloat = 3
    var isDark: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: digitSpacing) {
            SplitFlapDigit(value: String(tens), cardSize: cardSize, isDark: isDark, compact: compact)
            SplitFlapDigit(value: String(ones), cardSize: cardSize, isDark: isDark, compact: compact)
        }
    }
}
