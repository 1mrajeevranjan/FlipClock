import AppKit
import CoreText
import SwiftUI

/// Renders and caches card faces (digits "0"-"9", or short labels like
/// "AM"/"PM") as bitmaps, so the flip animation never re-rasterizes text
/// every tick — it just swaps cached CGImages between static cards and the
/// animating flap layer.
enum DigitFaceRenderer {
    private static var fullCache: [SizeKey: [String: CGImage]] = [:]
    private static var halfCache: [HalfKey: CGImage] = [:]

    private struct SizeKey: Hashable {
        let width: Int
        let height: Int
        let isDark: Bool
        let transparentBackground: Bool
        let fillColor: String
        let fontIdentifier: String
    }

    private struct HalfKey: Hashable {
        let value: String
        let width: Int
        let height: Int
        let top: Bool
        let isDark: Bool
        let transparentBackground: Bool
        let fillColor: String
        let fontIdentifier: String
    }

    /// Cache-key component for the font — without this, switching fonts
    /// would keep serving cached glyph bitmaps rendered in the previous
    /// font instead of re-rendering.
    private static func fontIdentifier(fontName: String?, isMonospacedSystemFont: Bool) -> String {
        if isMonospacedSystemFont { return "sfmono" }
        return fontName ?? "system"
    }

    static func face(for value: String, size: CGSize, isDark: Bool) -> CGImage {
        face(for: value, size: size, isDark: isDark, textColor: nil)
    }

    static func face(for value: String, size: CGSize, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fontName: String? = nil, isMonospacedSystemFont: Bool = false, tint: Color? = nil) -> CGImage {
        let key = SizeKey(width: Int(size.width.rounded()), height: Int(size.height.rounded()), isDark: isDark, transparentBackground: transparentBackground, fillColor: tint.map { NSColor($0).description } ?? "leaf", fontIdentifier: fontIdentifier(fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
        let cacheKey = cacheKey(for: value, textColor: textColor)
        if let image = fullCache[key]?[cacheKey] {
            return image
        }
        let image = render(value: value, fullSize: size, half: nil, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont, tint: tint)
        fullCache[key, default: [:]][cacheKey] = image
        return image
    }

    /// Top or bottom half of a card's face, for the static half-cards and
    /// for the animating flap's two content phases.
    static func halfFace(for value: String, cardSize: CGSize, top: Bool, isDark: Bool) -> CGImage {
        halfFace(for: value, cardSize: cardSize, top: top, isDark: isDark, textColor: nil)
    }

    /// `transparentBackground` skips the fill entirely — used for the
    /// "liquid glass" card style's idle static halves, where a real
    /// blurred `NSVisualEffectView` sits behind this image and the digit
    /// needs to read as drawn directly on top of that glass.
    ///
    /// `fillColor` overrides the default opaque leaf color when a fill is
    /// drawn — used by the animating flap in glass mode, which needs to
    /// stay opaque enough to fully mask the static digit underneath (or
    /// it "ghosts"/double-exposes mid-flip) while still reading as
    /// translucent glass rather than a solid leaf card, so the card
    /// doesn't visibly flash to a different color for the flip's duration.
    static func halfFace(for value: String, cardSize: CGSize, top: Bool, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false, tint: Color? = nil) -> CGImage {
        let key = HalfKey(
            value: cacheKey(for: value, textColor: textColor),
            width: Int(cardSize.width.rounded()),
            height: Int(cardSize.height.rounded()),
            top: top,
            isDark: isDark,
            transparentBackground: transparentBackground,
            fillColor: fillColor?.description ?? tint.map { NSColor($0).description } ?? "leaf",
            fontIdentifier: fontIdentifier(fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
        )
        if let image = halfCache[key] {
            return image
        }
        let image = render(value: value, fullSize: cardSize, half: top ? .top : .bottom, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground, fillColor: fillColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont, tint: tint)
        halfCache[key] = image
        return image
    }

    private enum Half { case top, bottom }

    /// Draws the glyph(s) as they would appear centered on a full-size
    /// card, but into a bitmap that may only be the top or bottom half of
    /// that card — the glyph lands cut exactly at the hinge line, matching
    /// the physical two-housing split-flap card.
    private static func render(value: String, fullSize: CGSize, half: Half?, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false, tint: Color? = nil) -> CGImage {
        let outputSize = half == nil ? fullSize : CGSize(width: fullSize.width, height: fullSize.height / 2)
        let nsImage = NSImage(size: outputSize)
        nsImage.lockFocus()

        if !transparentBackground {
            (fillColor ?? NSColor(FlapColors.leaf(isDark: isDark, tint: tint))).setFill()
            CGRect(origin: .zero, size: outputSize).fill()
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            nsImage.unlockFocus()
            fatalError("DigitFaceRenderer: no graphics context")
        }

        let line = line(for: value, fullSize: fullSize, isDark: isDark, textColor: textColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)

        // The line's actual rendered ink box (not typographic ascent/
        // descent/cap-height, which vary by font design and were still
        // leaving the glyph a few px off the true visual center) — this is
        // what "50% of the number height" means for a mixed-shape glyph
        // set like digits.
        let ink = CTLineGetImageBounds(line, context)

        // Origin such that the ink box's own center lands on the target
        // center — full card's midpoint, or that midpoint shifted by half
        // a card height for the top-half bitmap (see below).
        let targetCenterY = fullSize.height / 2
        let fullCardOriginY = targetCenterY - ink.midY
        let originX = (fullSize.width - ink.width) / 2 - ink.minX

        let originY: CGFloat
        switch half {
        case nil, .bottom:
            originY = fullCardOriginY
        case .top:
            originY = fullCardOriginY - fullSize.height / 2
        }

        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)
        nsImage.unlockFocus()

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("DigitFaceRenderer: failed to rasterize digit face")
        }
        return cgImage
    }

    private static func cacheKey(for value: String, textColor: NSColor?) -> String {
        guard let textColor else { return value }
        return "\(value)|\(textColor.description)"
    }

    private static func line(for value: String, fullSize: CGSize, isDark: Bool, textColor: NSColor?, fontName: String? = nil, isMonospacedSystemFont: Bool = false) -> CTLine {
        let maxWidth = fullSize.width * 0.82
        var fontSize = fullSize.height * 0.78
        var attributes: [NSAttributedString.Key: Any] = [:]

        while fontSize > 6 {
            let font: NSFont
            if isMonospacedSystemFont {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy)
            } else if let fontName, let named = NSFont(name: fontName, size: fontSize) {
                font = named
            } else {
                font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
            }
            attributes = [
                .font: font,
                .foregroundColor: textColor ?? NSColor(FlapColors.digit(isDark: isDark))
            ]
            let size = (value as NSString).size(withAttributes: attributes)
            if size.width <= maxWidth {
                break
            }
            fontSize -= 1
        }

        return CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    }
}
