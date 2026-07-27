import SwiftUI

enum FlapColors {
    static func leaf(isDark: Bool) -> Color {
        isDark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.93)
    }

    /// Solid, fully opaque — not a translucent shadow tint (that read as
    /// a faint smudge instead of a clear seam). Matches the *background*
    /// tone rather than the digit color: dark theme's card is near-black,
    /// so the seam is dark; light theme's card is near-white, so the seam
    /// is white. A crease blends into the card it's part of, it doesn't
    /// compete with the digits for contrast.
    static func leafHinge(isDark: Bool) -> Color {
        isDark ? Color.black : Color.white
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
    static func frostedCard(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.22, green: 0.25, blue: 0.30)
            : Color(red: 0.86, green: 0.89, blue: 0.93)
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
