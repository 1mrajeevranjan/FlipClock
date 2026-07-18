import SwiftUI

enum FlapColors {
    static func leaf(isDark: Bool) -> Color {
        isDark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.93)
    }

    static func leafHinge(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.4) }
        return isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
    }

    /// Opaque "frosted glass" fill for glass-style cards. Both the resting
    /// card face and the animating flap use this same tone, so a flip never
    /// changes the card's appearance — the flap is opaque (required, or the
    /// old digit ghosts through mid-rotation), and because the resting card
    /// is the identical opaque tone there is no transparent/live-blur state
    /// for it to flash away from.
    ///
    /// This is deliberately opaque, not a live blur: a static rasterized
    /// flap face can never sample a live `NSVisualEffectView` blur, so any
    /// see-through/live-blur resting card is fundamentally impossible for
    /// the flap to match, and the flip flashes. A fixed frosted tone that
    /// reads as glass sidesteps that entirely. The floating widget panel
    /// behind the cards (`WidgetGlassBackground`) stays real live glass.
    static func frostedCard(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.3) }
        return isDark
            ? Color(red: 0.22, green: 0.25, blue: 0.30)
            : Color(red: 0.86, green: 0.89, blue: 0.93)
    }

    static func digit(isDark: Bool) -> Color {
        isDark ? Color.white : Color.black
    }

    static func separatorDot(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.85) }
        return isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.5)
    }

    static let chromeTop = Color(white: 0.92)
    static let chromeBottom = Color(white: 0.45)
    static let chromeHighlight = Color(white: 0.99)
}
