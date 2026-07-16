import SwiftUI

enum FlapColors {
    static func leaf(isDark: Bool) -> Color {
        isDark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.93)
    }

    static func leafHinge(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
    }

    static func digit(isDark: Bool) -> Color {
        isDark ? Color.white : Color.black
    }

    static func separatorDot(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.5)
    }

    static let chromeTop = Color(white: 0.92)
    static let chromeBottom = Color(white: 0.45)
    static let chromeHighlight = Color(white: 0.99)
}
