import SwiftUI

enum FlapColors {
    static func leaf(isDark: Bool) -> Color {
        isDark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.93)
    }

    static func leafHinge(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
    }

    /// Fill for the animating flap in "liquid glass" cards. It has to stay
    /// opaque enough to fully mask the static digit underneath while
    /// mid-rotation (or the old glyph "ghosts" through), but a flat
    /// near-black/near-white leaf fill flashes as a jarringly different
    /// color against the translucent glass card it interrupts for a
    /// fraction of a second on every tick. This neutral, mostly-opaque
    /// tone reads close enough to a frosted glass surface in both
    /// appearances to avoid that flash, without depending on a live blur
    /// sample (not available for a static rasterized flap face).
    ///
    /// Measured against the desktop overlay's actual on-screen composite
    /// (`.underWindowBackground` blur + wallpaper): a resting card reads as
    /// a mid-brightness, faintly cool gray (~RGB 130-156), while the
    /// previous `white: 0.85` fill rendered flatly near-white (~RGB 211) —
    /// a stark, visible mismatch on every single flip. A neutral mid-gray
    /// sits far closer to that measured tone and, being roughly the
    /// midpoint of the brightness range rather than pinned to one end,
    /// keeps worst-case contrast lower across differently-lit wallpapers
    /// than a near-white fill ever could.
    static let glassFlapFill = Color(white: 0.55, opacity: 0.88)

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
