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

private struct CardTintKey: EnvironmentKey {
    static let defaultValue: CardTint = .standard
}

/// Frosted cards let what's behind them show through, blurred. On a widget's
/// own frosted panel that blur is already there, so the card only has to turn
/// translucent; with Fill screen the panel is fully clear and each card has to
/// blur the desktop itself.
enum CardFrost {
    case off, onPanel, overDesktop
}

private struct CardFrostKey: EnvironmentKey {
    static let defaultValue: CardFrost = .off
}

extension EnvironmentValues {
    /// Set once at a widget's root; every glass card below reads it, so the
    /// tone doesn't have to be threaded through each flap view's initializer.
    var glassTone: GlassTone {
        get { self[GlassToneKey.self] }
        set { self[GlassToneKey.self] = newValue }
    }

    /// Set at the desktop widgets' roots alongside `glassTone`; surfaces that
    /// don't set it (popover, menu bar) keep the default face.
    var cardTint: CardTint {
        get { self[CardTintKey.self] }
        set { self[CardTintKey.self] = newValue }
    }

    var cardFrost: CardFrost {
        get { self[CardFrostKey.self] }
        set { self[CardFrostKey.self] = newValue }
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
    /// like the system's own. A `CardTint` only colours the full-colour face.
    static func glassCardFill(isDark: Bool, tone: GlassTone, tint: CardTint = .standard, frosted: Bool = false) -> Color {
        if frosted { return frostedFill(tone: tone, tint: tint) }
        switch tone {
        case .vivid:
            if let fill = tint.fill { return Color(nsColor: fill).opacity(0.94) }
            return isDark ? Color(white: 0.17).opacity(0.94) : Color.white.opacity(0.94)
        case .monochrome, .dimmed: return Color.white.opacity(0.14)
        }
    }

    /// Frosted cards are dark smoked glass with white glyphs, close to the
    /// look the dimmed widget already has, so they read on any wallpaper.
    /// A milky light frost under white glyphs washed both out. The tint is
    /// only a hint over that, and Monochrome stays colourless.
    static func frostedFill(tone: GlassTone, tint: CardTint) -> Color {
        guard tone != .monochrome, let fill = tint.fill else { return Color.black.opacity(0.22) }
        return Color(nsColor: fill.blended(withFraction: 0.3, of: .black) ?? fill).opacity(0.45)
    }

    static let frostedGlyph = NSColor.white.withAlphaComponent(0.95)

    /// Light catching the top of a frosted card, fading out by the middle.
    static let frostedSheen = LinearGradient(
        colors: [.white.opacity(0.14), .white.opacity(0)],
        startPoint: .top,
        endPoint: .center
    )

    static let frostedRim = Color.white.opacity(0.25)

    /// Glyph colour on glass cards: theme-coloured (or the tint's contrast
    /// colour) on the solid full-colour cards, soft white on the translucent
    /// Monochrome/dimmed ones.
    static func glassGlyph(isDark: Bool, tone: GlassTone, tint: CardTint = .standard) -> NSColor {
        switch tone {
        case .vivid: return tint.glyph ?? (isDark ? .white : NSColor.black.withAlphaComponent(0.85))
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
