import SwiftUI
import AppKit

enum FlapColors {
    static func leaf(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tintedPanel(tint, isDark: isDark) }
        return isDark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.93)
    }

    /// Fixed regardless of tint — deliberately not tint-derived. Tinting
    /// this line too made it blend into whatever tint the digits use,
    /// which read as "the flip line changes with every tint color"; a
    /// constant line reads as the physical seam it represents no matter
    /// what accent color the cards are wearing.
    static func leafHinge(isDark: Bool, tint: Color? = nil) -> Color {
        if tint != nil { return Color.white.opacity(0.5) }
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
        if let tint { return tintedPanel(tint, isDark: isDark) }
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

    /// A fully-opaque card background derived from `tint`, blended toward
    /// black (dark appearance) or white (light appearance). Two reasons it
    /// must be blended rather than the raw tint:
    ///
    /// 1. **Opacity.** `frostedCard` feeds both the resting card AND the
    ///    animating flap's rasterized bitmap (`DigitFaceRenderer`). The flap
    ///    must stay fully opaque or the stale digit underneath bleeds
    ///    through mid-flip — using `tint.opacity(...)` here reintroduced
    ///    exactly that "glass changes on every flip" bug, now specific to
    ///    tinted mode.
    /// 2. **Contrast.** Digit ink also uses the raw `tint` color directly
    ///    (see `SplitFlapDigit.effectiveTextColor`). If the card background
    ///    were the same raw tint, ink and background would be identical —
    ///    invisible digits, which is what made the menu bar clock
    ///    unreadable once tinted. Blending toward black/white guarantees
    ///    the card reads as a distinct, darker/lighter tone than the ink
    ///    drawn on top of it, for any tint color the user picks.
    private static func tintedPanel(_ tint: Color, isDark: Bool) -> Color {
        let tintRGB = NSColor(tint).usingColorSpace(.deviceRGB) ?? NSColor(tint)
        let blend: CGFloat = isDark ? 0.35 : 0.22
        let base: CGFloat = isDark ? 0.0 : 1.0
        let red = tintRGB.redComponent * blend + base * (1 - blend)
        let green = tintRGB.greenComponent * blend + base * (1 - blend)
        let blue = tintRGB.blueComponent * blend + base * (1 - blend)
        return Color(red: red, green: green, blue: blue)
    }
}
