import SwiftUI
import AppKit

/// The three looks macOS gives a desktop widget: full colour, the user's
/// Monochrome pick, and the system's dimmed state while an app is in front.
enum GlassTone: Equatable {
    case vivid, monochrome, dimmed

    /// Vivid <-> dimmed completes within 5-10ms — one frame at 120Hz — as
    /// explicitly specified, so it reads as an immediate switch. That only
    /// works because nothing is rendered at switch time: the dimmed backdrop
    /// is pre-blurred (`DesktopBackdropCapture.dimmedImage`) and every card's
    /// faces for the other look are pre-rasterised (`FlipCardLayer`'s
    /// `upcomingStyles`). One shared timing keeps every layer in step.
    static let transitionDuration: Double = 0.008
    static let transitionCurve = (c0x: 0.25, c0y: 0.1, c1x: 0.25, c1y: 1.0)
    static let transition = Animation.timingCurve(
        transitionCurve.c0x, transitionCurve.c0y, transitionCurve.c1x, transitionCurve.c1y,
        duration: transitionDuration
    )
}

private struct GlassToneKey: EnvironmentKey {
    static let defaultValue: GlassTone = .vivid
}

extension EnvironmentValues {
    /// Set once at a widget's root; every glass card below reads it, so the
    /// tone doesn't have to be threaded through each flap view's initializer.
    var glassTone: GlassTone {
        get { self[GlassToneKey.self] }
        set { self[GlassToneKey.self] = newValue }
    }
}

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

    /// Card face on glass cards. Full colour matches the Calendar widget's
    /// near-solid white (dark grey in Dark mode) face; Monochrome and dimmed
    /// fall back to a faint translucent platter so the whole widget recedes,
    /// like the system's own.
    static func glassCardFill(isDark: Bool, tone: GlassTone) -> Color {
        switch tone {
        case .vivid: return isDark ? Color(white: 0.17).opacity(0.94) : Color.white.opacity(0.94)
        case .monochrome, .dimmed: return Color.white.opacity(0.14)
        }
    }

    /// Glyph colour on glass cards: theme-coloured on the solid full-colour
    /// cards, soft white on the translucent Monochrome/dimmed ones.
    static func glassGlyph(isDark: Bool, tone: GlassTone) -> NSColor {
        switch tone {
        case .vivid: return isDark ? .white : NSColor.black.withAlphaComponent(0.85)
        case .monochrome, .dimmed: return NSColor.white.withAlphaComponent(0.82)
        }
    }

    static func glassSeparator(isDark: Bool, tone: GlassTone) -> Color {
        Color(nsColor: glassGlyph(isDark: isDark, tone: tone)).opacity(0.7)
    }

    /// The split between a glass card's two leaves — a dark gap, like the
    /// real mechanism, strong enough to read on both the solid white
    /// full-colour cards and the translucent dimmed ones.
    static let glassHinge = NSColor.black.withAlphaComponent(0.62)

    /// Shade on the moving leaf of a glass card, so the flap reads as a
    /// surface catching less light while it turns rather than a glyph
    /// floating on its own.
    static let glassFlapShade = NSColor.black.withAlphaComponent(0.06)

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
