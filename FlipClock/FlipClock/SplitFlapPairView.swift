import SwiftUI

/// Two digits (e.g. "HH"), each its own independent card with a gap
/// between them — every digit in the clock is a separate module.
struct SplitFlapPairView: View {
    let tens: Int
    let ones: Int
    let cardSize: CGSize
    var digitSpacing: CGFloat = 3
    var isDark: Bool = true
    var compact: Bool = false
    var glassCard: Bool = false
    var showOwnGlassPanel: Bool = true

    var body: some View {
        HStack(spacing: digitSpacing) {
            SplitFlapDigit(value: String(tens), cardSize: cardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
            SplitFlapDigit(value: String(ones), cardSize: cardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
        }
    }
}
