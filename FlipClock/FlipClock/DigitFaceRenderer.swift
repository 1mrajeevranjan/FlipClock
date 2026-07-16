import AppKit
import CoreText

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
    }

    private struct HalfKey: Hashable {
        let value: String
        let width: Int
        let height: Int
        let top: Bool
        let isDark: Bool
    }

    static func face(for value: String, size: CGSize, isDark: Bool) -> CGImage {
        let key = SizeKey(width: Int(size.width.rounded()), height: Int(size.height.rounded()), isDark: isDark)
        if let image = fullCache[key]?[value] {
            return image
        }
        let image = render(value: value, fullSize: size, half: nil, isDark: isDark)
        fullCache[key, default: [:]][value] = image
        return image
    }

    /// Top or bottom half of a card's face, for the static half-cards and
    /// for the animating flap's two content phases.
    static func halfFace(for value: String, cardSize: CGSize, top: Bool, isDark: Bool) -> CGImage {
        let key = HalfKey(
            value: value,
            width: Int(cardSize.width.rounded()),
            height: Int(cardSize.height.rounded()),
            top: top,
            isDark: isDark
        )
        if let image = halfCache[key] {
            return image
        }
        let image = render(value: value, fullSize: cardSize, half: top ? .top : .bottom, isDark: isDark)
        halfCache[key] = image
        return image
    }

    private enum Half { case top, bottom }

    /// Draws the glyph(s) as they would appear centered on a full-size
    /// card, but into a bitmap that may only be the top or bottom half of
    /// that card — the glyph lands cut exactly at the hinge line, matching
    /// the physical two-housing split-flap card.
    private static func render(value: String, fullSize: CGSize, half: Half?, isDark: Bool) -> CGImage {
        let outputSize = half == nil ? fullSize : CGSize(width: fullSize.width, height: fullSize.height / 2)
        let nsImage = NSImage(size: outputSize)
        nsImage.lockFocus()

        NSColor(FlapColors.leaf(isDark: isDark)).setFill()
        CGRect(origin: .zero, size: outputSize).fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            nsImage.unlockFocus()
            fatalError("DigitFaceRenderer: no graphics context")
        }

        let fontSize = fullSize.height * 0.78
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(FlapColors.digit(isDark: isDark))
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attrs))

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
}
