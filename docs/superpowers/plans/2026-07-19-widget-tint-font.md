# Widget Tint + Font Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a custom HIG-style accent tint and a font for the split-flap clock, applied consistently across the desktop overlay widget, the popover, and the menu bar clock(s).

**Architecture:** Two new optional parameters (`tintColor: Color?`, plus `fontName: String?`/`isMonospacedSystemFont: Bool`) thread down the existing shared rendering chain (`SplitFlapClockFace` → `SplitFlapPairView`/`SplitFlapDigit` → `DigitFaceRenderer`/`FlipCardLayer`/`WidgetGlassBackground`). All new parameters default to values that reproduce today's exact behavior, so every existing call site keeps compiling and looking identical until a task explicitly wires real settings values into it.

**Tech Stack:** Swift 5.0, SwiftUI + AppKit, no external dependencies, no test target (see `CLAUDE.md`).

## Global Constraints

- New `AppSettings` properties: `widgetFont: WidgetFont` (default `.system`), `widgetTintEnabled: Bool` (default `false`), `widgetTintColor: Color` (default hex `#007AFF`, persisted as a hex string).
- `WidgetFont` cases and exact PostScript names: `system` (nil → `NSFont.systemFont`), `sfMono` (nil → `NSFont.monospacedSystemFont`, disambiguated via `isMonospacedSystem`), `menlo` (`"Menlo-Bold"`), `avenirNext` (`"AvenirNext-Heavy"`), `helveticaCondensed` (`"HelveticaNeue-CondensedBlack"`), `courier` (`"Courier-Bold"`).
- Tint opacities: hinge line `0.4`, frosted card `0.3`, separator dot `0.85`, `WidgetGlassBackground` overlay wash `0.18`. Digit ink uses the tint color directly (opacity `1.0`, it's already text ink).
- Tint priority: when `widgetTintEnabled` is true, the tint color overrides the existing Sunday-red weekday-text color — never both.
- Scope boundary: tint/font apply to the split-flap clock and date-row digits only. `CalendarMonthView` (popover's calendar grid) is explicitly untouched.
- No new test target — verification is build success (`xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build`, must end `** BUILD SUCCEEDED **`) plus visual check per task.

---

### Task 1: Settings — `WidgetFont` enum and persisted tint/font properties

**Files:**
- Modify: `FlipClock/Settings/AppSettings.swift`

**Interfaces:**
- Produces: `enum WidgetFont: String, CaseIterable, Identifiable` with `.label: String`, `.postscriptName: String?`, `.isMonospacedSystem: Bool`; `AppSettings.widgetFont: WidgetFont`, `AppSettings.widgetTintEnabled: Bool`, `AppSettings.widgetTintColor: Color`; a private `Color(hex:)` init and `.hexString` var (file-scoped extension, used only within this file for persistence).
- Consumes: nothing (first task).

- [ ] **Step 1: Add `import AppKit`**

Change line 1-4 from:

```swift
import Foundation
import Combine
import ServiceManagement
import SwiftUI
```

to:

```swift
import Foundation
import Combine
import ServiceManagement
import SwiftUI
import AppKit
```

- [ ] **Step 2: Add the `WidgetFont` enum**

Insert after the `MeridiemStyle` enum's closing brace (after line 105, before the `/// Single source of truth...` doc comment on line 107):

```swift

enum WidgetFont: String, CaseIterable, Identifiable {
    case system, sfMono, menlo, avenirNext, helveticaCondensed, courier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .avenirNext: return "Avenir Next"
        case .helveticaCondensed: return "Helvetica Condensed"
        case .courier: return "Courier"
        }
    }

    /// PostScript name for `NSFont(name:size:)`. `nil` means either the
    /// plain system font (`.system`) or the monospaced system font
    /// (`.sfMono`, resolved via `NSFont.monospacedSystemFont` since that's
    /// the correct API for it, not a PostScript name lookup) —
    /// `isMonospacedSystem` disambiguates the two `nil` cases.
    var postscriptName: String? {
        switch self {
        case .system, .sfMono: return nil
        case .menlo: return "Menlo-Bold"
        case .avenirNext: return "AvenirNext-Heavy"
        case .helveticaCondensed: return "HelveticaNeue-CondensedBlack"
        case .courier: return "Courier-Bold"
        }
    }

    var isMonospacedSystem: Bool { self == .sfMono }
}
```

- [ ] **Step 3: Add the three new `@Published` properties**

Insert directly after the `fillScreen` property's closing brace (after line 178, before `private enum Keys {` on line 180):

```swift

    @Published var widgetFont: WidgetFont {
        didSet { UserDefaults.standard.set(widgetFont.rawValue, forKey: Keys.widgetFont) }
    }

    @Published var widgetTintEnabled: Bool {
        didSet { UserDefaults.standard.set(widgetTintEnabled, forKey: Keys.widgetTintEnabled) }
    }

    /// The HIG-style accent tint applied across the clock when
    /// `widgetTintEnabled` is true. Persisted as a hex string (`Color`
    /// itself isn't a `UserDefaults`-storable type) — alpha isn't part of
    /// the stored value, every consumer applies its own fixed opacity.
    @Published var widgetTintColor: Color {
        didSet { UserDefaults.standard.set(widgetTintColor.hexString, forKey: Keys.widgetTintColor) }
    }
```

- [ ] **Step 4: Add the three new `Keys`**

Change the `Keys` enum (lines 180-193) from:

```swift
    private enum Keys {
        static let showDesktopOverlay = "showDesktopOverlay"
        static let launchAtLogin = "launchAtLogin"
        static let theme = "theme"
        static let popoverGlassiness = "popoverGlassiness"
        static let overlaySize = "overlaySize"
        static let meridiemStyle = "meridiemStyle"
        static let showSecondClock = "showSecondClock"
        static let secondTimezoneID = "secondTimezoneID"
        static let timeFormat = "timeFormat"
        static let showDateOnOverlay = "showDateOnOverlay"
        static let floatAcrossScreen = "floatAcrossScreen"
        static let fillScreen = "fillScreen"
    }
```

to:

```swift
    private enum Keys {
        static let showDesktopOverlay = "showDesktopOverlay"
        static let launchAtLogin = "launchAtLogin"
        static let theme = "theme"
        static let popoverGlassiness = "popoverGlassiness"
        static let overlaySize = "overlaySize"
        static let meridiemStyle = "meridiemStyle"
        static let showSecondClock = "showSecondClock"
        static let secondTimezoneID = "secondTimezoneID"
        static let timeFormat = "timeFormat"
        static let showDateOnOverlay = "showDateOnOverlay"
        static let floatAcrossScreen = "floatAcrossScreen"
        static let fillScreen = "fillScreen"
        static let widgetFont = "widgetFont"
        static let widgetTintEnabled = "widgetTintEnabled"
        static let widgetTintColor = "widgetTintColor"
    }
```

- [ ] **Step 5: Initialize the three properties in `init()`**

Change the end of `init()` (lines 195-209) from:

```swift
    init() {
        let defaults = UserDefaults.standard
        showDesktopOverlay = defaults.object(forKey: Keys.showDesktopOverlay) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        theme = (defaults.string(forKey: Keys.theme)).flatMap(AppTheme.init(rawValue:)) ?? .system
        popoverGlassiness = defaults.object(forKey: Keys.popoverGlassiness) as? Double ?? 0.7
        overlaySize = (defaults.string(forKey: Keys.overlaySize)).flatMap(OverlaySize.init(rawValue:)) ?? .full
        meridiemStyle = (defaults.string(forKey: Keys.meridiemStyle)).flatMap(MeridiemStyle.init(rawValue:)) ?? .text
        showSecondClock = defaults.object(forKey: Keys.showSecondClock) as? Bool ?? false
        secondTimezoneID = defaults.string(forKey: Keys.secondTimezoneID) ?? "UTC"
        timeFormat = (defaults.string(forKey: Keys.timeFormat)).flatMap(TimeFormat.init(rawValue:)) ?? .twelveHour
        showDateOnOverlay = defaults.object(forKey: Keys.showDateOnOverlay) as? Bool ?? true
        floatAcrossScreen = defaults.object(forKey: Keys.floatAcrossScreen) as? Bool ?? false
        fillScreen = defaults.object(forKey: Keys.fillScreen) as? Bool ?? false
    }
```

to:

```swift
    init() {
        let defaults = UserDefaults.standard
        showDesktopOverlay = defaults.object(forKey: Keys.showDesktopOverlay) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        theme = (defaults.string(forKey: Keys.theme)).flatMap(AppTheme.init(rawValue:)) ?? .system
        popoverGlassiness = defaults.object(forKey: Keys.popoverGlassiness) as? Double ?? 0.7
        overlaySize = (defaults.string(forKey: Keys.overlaySize)).flatMap(OverlaySize.init(rawValue:)) ?? .full
        meridiemStyle = (defaults.string(forKey: Keys.meridiemStyle)).flatMap(MeridiemStyle.init(rawValue:)) ?? .text
        showSecondClock = defaults.object(forKey: Keys.showSecondClock) as? Bool ?? false
        secondTimezoneID = defaults.string(forKey: Keys.secondTimezoneID) ?? "UTC"
        timeFormat = (defaults.string(forKey: Keys.timeFormat)).flatMap(TimeFormat.init(rawValue:)) ?? .twelveHour
        showDateOnOverlay = defaults.object(forKey: Keys.showDateOnOverlay) as? Bool ?? true
        floatAcrossScreen = defaults.object(forKey: Keys.floatAcrossScreen) as? Bool ?? false
        fillScreen = defaults.object(forKey: Keys.fillScreen) as? Bool ?? false
        widgetFont = (defaults.string(forKey: Keys.widgetFont)).flatMap(WidgetFont.init(rawValue:)) ?? .system
        widgetTintEnabled = defaults.object(forKey: Keys.widgetTintEnabled) as? Bool ?? false
        widgetTintColor = (defaults.string(forKey: Keys.widgetTintColor)).map(Color.init(hex:)) ?? Color(hex: "007AFF")
    }
```

- [ ] **Step 6: Add the `Color` hex bridge**

Insert at the very end of the file, after the closing brace of `AppSettings` (after the current final `}` that closes `applyLaunchAtLogin`'s enclosing class, i.e. append after line 225):

```swift

private extension Color {
    /// RGB-only hex string (no alpha) for `UserDefaults` persistence —
    /// tint is always applied at a fixed opacity by each renderer, not by
    /// the stored color itself.
    var hexString: String {
        guard let converted = NSColor(self).usingColorSpace(.deviceRGB) else { return "007AFF" }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        let red = Double((rgb & 0xFF0000) >> 16) / 255
        let green = Double((rgb & 0x00FF00) >> 8) / 255
        let blue = Double(rgb & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
```

- [ ] **Step 7: Build**

```bash
cd /Users/rajeevranjan/ClaudeCode/Clock
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`. Nothing in the UI changes yet — these properties aren't read anywhere.

- [ ] **Step 8: Commit**

```bash
git add FlipClock/Settings/AppSettings.swift
git commit -m "feat: add WidgetFont enum and persisted tint/font settings"
```

---

### Task 2: Rendering primitives — tint-aware color tokens and font-aware glyph renderer

**Files:**
- Modify: `FlipClock/FlipClock/FlapColors.swift`
- Modify: `FlipClock/FlipClock/DigitFaceRenderer.swift`

**Interfaces:**
- Consumes: nothing new from Task 1 (pure rendering-layer changes, don't reference `AppSettings`).
- Produces: `FlapColors.leafHinge(isDark:tint:)`, `FlapColors.frostedCard(isDark:tint:)`, `FlapColors.separatorDot(isDark:tint:)` — all with `tint: Color? = nil` added to the existing signature, default preserves current behavior exactly. `DigitFaceRenderer.face(...)`, `.halfFace(...)`, private `.render(...)`, private `.line(for:...)` all gain `fontName: String? = nil, isMonospacedSystemFont: Bool = false` parameters (defaults preserve current system-font behavior).

- [ ] **Step 1: Add `tint` parameter to three `FlapColors` functions**

Change (in `FlapColors.swift`):

```swift
    static func leafHinge(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
    }
```

to:

```swift
    static func leafHinge(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.4) }
        return isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
    }
```

Change:

```swift
    static func frostedCard(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.22, green: 0.25, blue: 0.30)
            : Color(red: 0.86, green: 0.89, blue: 0.93)
    }
```

to:

```swift
    static func frostedCard(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.3) }
        return isDark
            ? Color(red: 0.22, green: 0.25, blue: 0.30)
            : Color(red: 0.86, green: 0.89, blue: 0.93)
    }
```

Change:

```swift
    static func separatorDot(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.5)
    }
```

to:

```swift
    static func separatorDot(isDark: Bool, tint: Color? = nil) -> Color {
        if let tint { return tint.opacity(0.85) }
        return isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.5)
    }
```

`digit(isDark:)` is NOT modified — tint reaches digit ink through the existing `textColor: NSColor?` override in `SplitFlapDigit`/`DigitFaceRenderer` (Task 3), not through this function.

- [ ] **Step 2: Add font parameters to `DigitFaceRenderer`'s cache keys**

Change:

```swift
    private struct SizeKey: Hashable {
        let width: Int
        let height: Int
        let isDark: Bool
        let transparentBackground: Bool
        let fillColor: String
    }

    private struct HalfKey: Hashable {
        let value: String
        let width: Int
        let height: Int
        let top: Bool
        let isDark: Bool
        let transparentBackground: Bool
        let fillColor: String
    }
```

to:

```swift
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
```

- [ ] **Step 3: Thread `fontName`/`isMonospacedSystemFont` through `face(for:...)`**

Change:

```swift
    static func face(for value: String, size: CGSize, isDark: Bool) -> CGImage {
        face(for: value, size: size, isDark: isDark, textColor: nil)
    }

    static func face(for value: String, size: CGSize, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false) -> CGImage {
        let key = SizeKey(width: Int(size.width.rounded()), height: Int(size.height.rounded()), isDark: isDark, transparentBackground: transparentBackground, fillColor: "leaf")
        let cacheKey = cacheKey(for: value, textColor: textColor)
        if let image = fullCache[key]?[cacheKey] {
            return image
        }
        let image = render(value: value, fullSize: size, half: nil, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground)
        fullCache[key, default: [:]][cacheKey] = image
        return image
    }
```

to:

```swift
    static func face(for value: String, size: CGSize, isDark: Bool) -> CGImage {
        face(for: value, size: size, isDark: isDark, textColor: nil)
    }

    static func face(for value: String, size: CGSize, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fontName: String? = nil, isMonospacedSystemFont: Bool = false) -> CGImage {
        let key = SizeKey(width: Int(size.width.rounded()), height: Int(size.height.rounded()), isDark: isDark, transparentBackground: transparentBackground, fillColor: "leaf", fontIdentifier: fontIdentifier(fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
        let cacheKey = cacheKey(for: value, textColor: textColor)
        if let image = fullCache[key]?[cacheKey] {
            return image
        }
        let image = render(value: value, fullSize: size, half: nil, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
        fullCache[key, default: [:]][cacheKey] = image
        return image
    }
```

- [ ] **Step 4: Thread `fontName`/`isMonospacedSystemFont` through the full `halfFace(for:...)` signature**

The zero-textColor convenience overload (`halfFace(for:cardSize:top:isDark:)`) is unused anywhere in the codebase (confirmed via `grep -rn "DigitFaceRenderer\." FlipClock/` — only the full signature below is ever called, always with `textColor:` explicit) — leave it untouched, don't add a font variant of it.

Change:

```swift
    static func halfFace(for value: String, cardSize: CGSize, top: Bool, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil) -> CGImage {
        let key = HalfKey(
            value: cacheKey(for: value, textColor: textColor),
            width: Int(cardSize.width.rounded()),
            height: Int(cardSize.height.rounded()),
            top: top,
            isDark: isDark,
            transparentBackground: transparentBackground,
            fillColor: fillColor?.description ?? "leaf"
        )
        if let image = halfCache[key] {
            return image
        }
        let image = render(value: value, fullSize: cardSize, half: top ? .top : .bottom, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground, fillColor: fillColor)
        halfCache[key] = image
        return image
    }
```

to:

```swift
    static func halfFace(for value: String, cardSize: CGSize, top: Bool, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false) -> CGImage {
        let key = HalfKey(
            value: cacheKey(for: value, textColor: textColor),
            width: Int(cardSize.width.rounded()),
            height: Int(cardSize.height.rounded()),
            top: top,
            isDark: isDark,
            transparentBackground: transparentBackground,
            fillColor: fillColor?.description ?? "leaf",
            fontIdentifier: fontIdentifier(fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
        )
        if let image = halfCache[key] {
            return image
        }
        let image = render(value: value, fullSize: cardSize, half: top ? .top : .bottom, isDark: isDark, textColor: textColor, transparentBackground: transparentBackground, fillColor: fillColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
        halfCache[key] = image
        return image
    }
```

- [ ] **Step 5: Thread `fontName`/`isMonospacedSystemFont` through `render(...)` and `line(for:...)`**

Change:

```swift
    private static func render(value: String, fullSize: CGSize, half: Half?, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil) -> CGImage {
```

to:

```swift
    private static func render(value: String, fullSize: CGSize, half: Half?, isDark: Bool, textColor: NSColor?, transparentBackground: Bool = false, fillColor: NSColor? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false) -> CGImage {
```

Inside `render`, change:

```swift
        let line = line(for: value, fullSize: fullSize, isDark: isDark, textColor: textColor)
```

to:

```swift
        let line = line(for: value, fullSize: fullSize, isDark: isDark, textColor: textColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
```

Change:

```swift
    private static func line(for value: String, fullSize: CGSize, isDark: Bool, textColor: NSColor?) -> CTLine {
        let maxWidth = fullSize.width * 0.82
        var fontSize = fullSize.height * 0.78
        var attributes: [NSAttributedString.Key: Any] = [:]

        while fontSize > 6 {
            let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
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
```

to:

```swift
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
```

- [ ] **Step 6: Build**

```bash
cd /Users/rajeevranjan/ClaudeCode/Clock
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`. No visible change yet — no call site passes a `tint`/`fontName` yet.

- [ ] **Step 7: Commit**

```bash
git add FlipClock/FlipClock/FlapColors.swift FlipClock/FlipClock/DigitFaceRenderer.swift
git commit -m "feat: add tint-aware color tokens and font-aware glyph rendering"
```

---

### Task 3: Thread tint/font through the shared view chain

**Files:**
- Modify: `FlipClock/FlipClock/SplitFlapDigit.swift`
- Modify: `FlipClock/FlipClock/FlipCardLayer.swift`
- Modify: `FlipClock/FlipClock/SplitFlapPairView.swift`
- Modify: `FlipClock/FlipClock/SplitFlapClockFace.swift`
- Modify: `FlipClock/DesktopOverlay/WidgetGlassBackground.swift`

**Interfaces:**
- Consumes: `FlapColors.leafHinge(isDark:tint:)`, `.frostedCard(isDark:tint:)`, `.separatorDot(isDark:tint:)` and `DigitFaceRenderer.halfFace(...fontName:isMonospacedSystemFont:)` from Task 2.
- Produces: `SplitFlapDigit(..., tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false)`, `FlipCardLayer(..., tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false)`, `SplitFlapPairView(..., tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false)`, `SplitFlapClockFace(..., tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false)`, `WidgetGlassBackground(..., tintColor: Color? = nil)`. All defaults reproduce current behavior exactly.

- [ ] **Step 1: `SplitFlapDigit.swift` — add the three new properties**

Change:

```swift
    var textColor: NSColor? = nil
```

to:

```swift
    var textColor: NSColor? = nil
    /// HIG-style accent tint. When set, this wins over `textColor` for the
    /// digit ink (a global "themed" mode beats the one-off Sunday-red
    /// weekday case), and also drives the hinge line and frosted-card fill
    /// via the tint-aware `FlapColors` overloads.
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
```

- [ ] **Step 2: `SplitFlapDigit.swift` — update the memberwise `init`**

Change:

```swift
    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil, fusedLeading: Bool = false, fusedTrailing: Bool = false, glassCard: Bool = false, showOwnGlassPanel: Bool = true) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        self.fusedLeading = fusedLeading
        self.fusedTrailing = fusedTrailing
        self.glassCard = glassCard
        self.showOwnGlassPanel = showOwnGlassPanel
        _topValue = State(initialValue: value)
        _bottomValue = State(initialValue: value)
    }
```

to:

```swift
    init(value: String, cardSize: CGSize, isDark: Bool = true, compact: Bool = false, textColor: NSColor? = nil, fusedLeading: Bool = false, fusedTrailing: Bool = false, glassCard: Bool = false, showOwnGlassPanel: Bool = true, tintColor: Color? = nil, fontName: String? = nil, isMonospacedSystemFont: Bool = false) {
        self.value = value
        self.cardSize = cardSize
        self.isDark = isDark
        self.compact = compact
        self.textColor = textColor
        self.fusedLeading = fusedLeading
        self.fusedTrailing = fusedTrailing
        self.glassCard = glassCard
        self.showOwnGlassPanel = showOwnGlassPanel
        self.tintColor = tintColor
        self.fontName = fontName
        self.isMonospacedSystemFont = isMonospacedSystemFont
        _topValue = State(initialValue: value)
        _bottomValue = State(initialValue: value)
    }
```

- [ ] **Step 3: `SplitFlapDigit.swift` — compute effective ink color, wire into `body`**

Change:

```swift
    private var cornerRadius: CGFloat { compact ? 2 : 6 }
```

to:

```swift
    private var cornerRadius: CGFloat { compact ? 2 : 6 }

    /// Tint wins over the `textColor` override (e.g. Sunday-red) when
    /// present — see the doc comment on `tintColor` above.
    private var effectiveTextColor: NSColor? {
        tintColor.map(NSColor.init) ?? textColor
    }
```

Change:

```swift
            if glassCard {
                // Opaque frosted base, drawn by a real drag-enabled NSView
                // (see `DraggableColorView`) so the desktop overlay stays
                // draggable by its background over the cards. The static
                // halves render their digit on a transparent background and
                // composite on top of this, so the resting card is exactly
                // "frosted tone + digit" — identical to what the flap draws.
                DraggableColorView(color: FlapColors.frostedCard(isDark: isDark)).clipShape(cardShape)
            }

            VStack(spacing: 0) {
                HalfCard(image: DigitFaceRenderer.halfFace(for: topValue, cardSize: cardSize, top: true, isDark: isDark, textColor: textColor, transparentBackground: glassCard))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
                HalfCard(image: DigitFaceRenderer.halfFace(for: bottomValue, cardSize: cardSize, top: false, isDark: isDark, textColor: textColor, transparentBackground: glassCard))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
            }
            .clipShape(cardShape)

            HingeLine(width: cardSize.width, isDark: isDark, compact: compact)

            // The animating leaf always renders opaque — it needs to fully
            // mask the static half underneath while it's mid-rotation, or
            // the old digit bleeds through the new one and reads as a
            // double-exposed "ghost" during the flip. In glass mode it
            // fills with the same `FlapColors.frostedCard` tone as the
            // resting halves, so the opaque flap is visually indistinct
            // from the resting card and the flip doesn't change the card's
            // appearance at all.
            FlipCardLayer(value: value, cardSize: cardSize, isDark: isDark, glassCard: glassCard) {
                bottomValue = value
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(cardShape)
```

to:

```swift
            if glassCard {
                // Opaque frosted base, drawn by a real drag-enabled NSView
                // (see `DraggableColorView`) so the desktop overlay stays
                // draggable by its background over the cards. The static
                // halves render their digit on a transparent background and
                // composite on top of this, so the resting card is exactly
                // "frosted tone + digit" — identical to what the flap draws.
                DraggableColorView(color: FlapColors.frostedCard(isDark: isDark, tint: tintColor)).clipShape(cardShape)
            }

            VStack(spacing: 0) {
                HalfCard(image: DigitFaceRenderer.halfFace(for: topValue, cardSize: cardSize, top: true, isDark: isDark, textColor: effectiveTextColor, transparentBackground: glassCard, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
                HalfCard(image: DigitFaceRenderer.halfFace(for: bottomValue, cardSize: cardSize, top: false, isDark: isDark, textColor: effectiveTextColor, transparentBackground: glassCard, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont))
                    .frame(width: cardSize.width, height: cardSize.height / 2)
            }
            .clipShape(cardShape)

            HingeLine(width: cardSize.width, isDark: isDark, compact: compact, tint: tintColor)

            // The animating leaf always renders opaque — it needs to fully
            // mask the static half underneath while it's mid-rotation, or
            // the old digit bleeds through the new one and reads as a
            // double-exposed "ghost" during the flip. In glass mode it
            // fills with the same `FlapColors.frostedCard` tone as the
            // resting halves, so the opaque flap is visually indistinct
            // from the resting card and the flip doesn't change the card's
            // appearance at all.
            FlipCardLayer(value: value, cardSize: cardSize, isDark: isDark, glassCard: glassCard, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont) {
                bottomValue = value
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(cardShape)
```

- [ ] **Step 4: `SplitFlapDigit.swift` — add `tint` to `HingeLine`**

Change:

```swift
private struct HingeLine: View {
    let width: CGFloat
    let isDark: Bool
    let compact: Bool

    private var coreHeight: CGFloat { compact ? 1.5 : 3.5 }

    var body: some View {
        Rectangle()
            .fill(FlapColors.leafHinge(isDark: isDark))
            .frame(width: width, height: coreHeight)
    }
}
```

to:

```swift
private struct HingeLine: View {
    let width: CGFloat
    let isDark: Bool
    let compact: Bool
    var tint: Color? = nil

    private var coreHeight: CGFloat { compact ? 1.5 : 3.5 }

    var body: some View {
        Rectangle()
            .fill(FlapColors.leafHinge(isDark: isDark, tint: tint))
            .frame(width: width, height: coreHeight)
    }
}
```

- [ ] **Step 5: `FlipCardLayer.swift` — add the three new properties**

Change:

```swift
struct FlipCardLayer: NSViewRepresentable {
    let value: String
    let cardSize: CGSize
    let isDark: Bool
    var glassCard: Bool = false
    var onLanded: () -> Void = {}

    func makeNSView(context: Context) -> FlapAnimatingNSView {
        let view = FlapAnimatingNSView()
        view.configure(cardSize: cardSize)
        context.coordinator.lastValue = value
        return view
    }

    func updateNSView(_ nsView: FlapAnimatingNSView, context: Context) {
        nsView.onLanded = onLanded
        nsView.isDark = isDark
        nsView.glassCard = glassCard
        nsView.configure(cardSize: cardSize)
        guard context.coordinator.lastValue != value else { return }
        let old = context.coordinator.lastValue
        context.coordinator.lastValue = value
        nsView.playFlip(oldValue: old, newValue: value)
    }
```

to:

```swift
struct FlipCardLayer: NSViewRepresentable {
    let value: String
    let cardSize: CGSize
    let isDark: Bool
    var glassCard: Bool = false
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
    var onLanded: () -> Void = {}

    func makeNSView(context: Context) -> FlapAnimatingNSView {
        let view = FlapAnimatingNSView()
        view.configure(cardSize: cardSize)
        context.coordinator.lastValue = value
        return view
    }

    func updateNSView(_ nsView: FlapAnimatingNSView, context: Context) {
        nsView.onLanded = onLanded
        nsView.isDark = isDark
        nsView.glassCard = glassCard
        nsView.tintColor = tintColor
        nsView.fontName = fontName
        nsView.isMonospacedSystemFont = isMonospacedSystemFont
        nsView.configure(cardSize: cardSize)
        guard context.coordinator.lastValue != value else { return }
        let old = context.coordinator.lastValue
        context.coordinator.lastValue = value
        nsView.playFlip(oldValue: old, newValue: value)
    }
```

- [ ] **Step 6: `FlipCardLayer.swift` — add matching stored properties on `FlapAnimatingNSView`**

Change:

```swift
final class FlapAnimatingNSView: NSView {
    var onLanded: (() -> Void)?
    var isDark: Bool = true
    var glassCard: Bool = false
```

to:

```swift
final class FlapAnimatingNSView: NSView {
    var onLanded: (() -> Void)?
    var isDark: Bool = true
    var glassCard: Bool = false
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
```

- [ ] **Step 7: `FlipCardLayer.swift` — use tint/font in both `halfFace` calls**

Change (phase 1, inside `playFlip`):

```swift
        flapLayer.contents = DigitFaceRenderer.halfFace(for: oldValue, cardSize: cardSize, top: true, isDark: isDark, textColor: nil, fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark)) : nil)
```

to:

```swift
        flapLayer.contents = DigitFaceRenderer.halfFace(for: oldValue, cardSize: cardSize, top: true, isDark: isDark, textColor: tintColor.map(NSColor.init), fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark, tint: tintColor)) : nil, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
```

Change (phase 2, inside `startPhase2`):

```swift
        flapLayer.contents = DigitFaceRenderer.halfFace(for: newValue, cardSize: cardSize, top: false, isDark: isDark, textColor: nil, fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark)) : nil)
```

to:

```swift
        flapLayer.contents = DigitFaceRenderer.halfFace(for: newValue, cardSize: cardSize, top: false, isDark: isDark, textColor: tintColor.map(NSColor.init), fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark, tint: tintColor)) : nil, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
```

- [ ] **Step 8: `SplitFlapPairView.swift` — thread the three params**

Replace the full file content with:

```swift
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
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false

    var body: some View {
        HStack(spacing: digitSpacing) {
            SplitFlapDigit(value: String(tens), cardSize: cardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
            SplitFlapDigit(value: String(ones), cardSize: cardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
        }
    }
}
```

- [ ] **Step 9: `SplitFlapClockFace.swift` — add the three new properties**

Change:

```swift
struct SplitFlapClockFace: View {
    let tick: ClockTick
    var scale: CGFloat = 1
    var compact: Bool = false
    var showPedestal: Bool = true
    var meridiemStyle: MeridiemStyle = .text
    var timeFormat: TimeFormat = .twelveHour
    var glassCard: Bool = false
    var showOwnGlassPanel: Bool = true
```

to:

```swift
struct SplitFlapClockFace: View {
    let tick: ClockTick
    var scale: CGFloat = 1
    var compact: Bool = false
    var showPedestal: Bool = true
    var meridiemStyle: MeridiemStyle = .text
    var timeFormat: TimeFormat = .twelveHour
    var glassCard: Bool = false
    var showOwnGlassPanel: Bool = true
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
```

- [ ] **Step 10: `SplitFlapClockFace.swift` — thread into `body`**

Change:

```swift
    var body: some View {
        let m = metrics
        let hour = tick.hourDigits(format: timeFormat)
        VStack(spacing: compact ? 0 : m.vGroupSpacing) {
            HStack(alignment: .center, spacing: m.rowSpacing) {
                SplitFlapPairView(tens: hour.tens, ones: hour.ones, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
                separator(m)
                SplitFlapPairView(tens: tick.minute / 10, ones: tick.minute % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
                separator(m)
                SplitFlapPairView(tens: tick.second / 10, ones: tick.second % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
                if showMeridiem {
                    HStack(spacing: m.digitSpacing) {
                        ForEach(Array(meridiemStyle.cards(isPM: tick.isPM).enumerated()), id: \.offset) { _, card in
                            SplitFlapDigit(value: card, cardSize: m.ampmCardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel)
                        }
                    }
                }
            }

            if !compact && showPedestal {
                Pedestal(width: m.pedestalWidth)
                    .frame(height: 28 * scale)
            }
        }
        .padding(.horizontal, m.horizontalPadding)
    }
```

to:

```swift
    var body: some View {
        let m = metrics
        let hour = tick.hourDigits(format: timeFormat)
        VStack(spacing: compact ? 0 : m.vGroupSpacing) {
            HStack(alignment: .center, spacing: m.rowSpacing) {
                SplitFlapPairView(tens: hour.tens, ones: hour.ones, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
                separator(m)
                SplitFlapPairView(tens: tick.minute / 10, ones: tick.minute % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
                separator(m)
                SplitFlapPairView(tens: tick.second / 10, ones: tick.second % 10, cardSize: m.digitCardSize, digitSpacing: m.digitSpacing, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
                if showMeridiem {
                    HStack(spacing: m.digitSpacing) {
                        ForEach(Array(meridiemStyle.cards(isPM: tick.isPM).enumerated()), id: \.offset) { _, card in
                            SplitFlapDigit(value: card, cardSize: m.ampmCardSize, isDark: isDark, compact: compact, glassCard: glassCard, showOwnGlassPanel: showOwnGlassPanel, tintColor: tintColor, fontName: fontName, isMonospacedSystemFont: isMonospacedSystemFont)
                        }
                    }
                }
            }

            if !compact && showPedestal {
                Pedestal(width: m.pedestalWidth)
                    .frame(height: 28 * scale)
            }
        }
        .padding(.horizontal, m.horizontalPadding)
    }
```

- [ ] **Step 11: `SplitFlapClockFace.swift` — tint the separator dots**

Change:

```swift
    private func separator(_ m: Metrics) -> some View {
        VStack(spacing: m.separatorDotGap) {
            Circle().frame(width: m.separatorDotSize)
            Circle().frame(width: m.separatorDotSize)
        }
        .foregroundStyle(FlapColors.separatorDot(isDark: isDark))
    }
```

to:

```swift
    private func separator(_ m: Metrics) -> some View {
        VStack(spacing: m.separatorDotGap) {
            Circle().frame(width: m.separatorDotSize)
            Circle().frame(width: m.separatorDotSize)
        }
        .foregroundStyle(FlapColors.separatorDot(isDark: isDark, tint: tintColor))
    }
```

- [ ] **Step 12: `WidgetGlassBackground.swift` — add `tintColor` and the wash overlay**

Change:

```swift
struct WidgetGlassBackground: View {
    /// The widget's `overlaySize.scale` (0.325/0.65/1.3/1.95) — drives both
    /// corner radius and shadow so they scale with widget size instead of
    /// staying fixed constants, per Apple's Widget HIG guidance that a
    /// widget's corner radius should track its container rather than be a
    /// flat value.
    var scale: CGFloat = 1
    /// Full-screen mode wants completely transparent glass — no blur, no
    /// tint, no stroke, no shadow, just the raw desktop showing through with
    /// the clock floating on top of it — rather than a widget-style frosted
    /// panel that would visibly gray out the whole screen.
    var fullyClear: Bool = false
```

to:

```swift
struct WidgetGlassBackground: View {
    /// The widget's `overlaySize.scale` (0.325/0.65/1.3/1.95) — drives both
    /// corner radius and shadow so they scale with widget size instead of
    /// staying fixed constants, per Apple's Widget HIG guidance that a
    /// widget's corner radius should track its container rather than be a
    /// flat value.
    var scale: CGFloat = 1
    /// Full-screen mode wants completely transparent glass — no blur, no
    /// tint, no stroke, no shadow, just the raw desktop showing through with
    /// the clock floating on top of it — rather than a widget-style frosted
    /// panel that would visibly gray out the whole screen.
    var fullyClear: Bool = false
    /// HIG-style accent tint — when set, washes a translucent tint-colored
    /// layer over the panel's blur, matching Apple's "tinted" widget
    /// appearance.
    var tintColor: Color? = nil
```

Change:

```swift
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .background(
                    VisualEffectBlur()
                        .opacity(0.22)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(
                    color: .black.opacity(0.18),
                    radius: (12 * scale).clamped(to: 6...20),
                    x: 0,
                    y: (4 * scale).clamped(to: 2...8)
                )
```

to:

```swift
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .background(
                    VisualEffectBlur()
                        .opacity(0.22)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .overlay {
                    if let tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tintColor.opacity(0.18))
                    }
                }
                .shadow(
                    color: .black.opacity(0.18),
                    radius: (12 * scale).clamped(to: 6...20),
                    x: 0,
                    y: (4 * scale).clamped(to: 2...8)
                )
```

- [ ] **Step 13: Build**

```bash
cd /Users/rajeevranjan/ClaudeCode/Clock
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`. Still no visible change — no call site in `OverlayContentView`/`MenuBarClockView`/`SecondClockMenuBarView`/`PopoverClockView` passes real settings values yet (Task 4).

- [ ] **Step 14: Commit**

```bash
git add FlipClock/FlipClock/SplitFlapDigit.swift FlipClock/FlipClock/FlipCardLayer.swift FlipClock/FlipClock/SplitFlapPairView.swift FlipClock/FlipClock/SplitFlapClockFace.swift FlipClock/DesktopOverlay/WidgetGlassBackground.swift
git commit -m "feat: thread tint/font parameters through the shared rendering chain"
```

---

### Task 4: Wire settings into all call sites, add Settings UI

**Files:**
- Modify: `FlipClock/DesktopOverlay/OverlayContentView.swift`
- Modify: `FlipClock/MenuBar/MenuBarClockView.swift`
- Modify: `FlipClock/MenuBar/SecondClockMenuBarView.swift`
- Modify: `FlipClock/Popover/PopoverClockView.swift`
- Modify: `FlipClock/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `AppSettings.widgetFont/.widgetTintEnabled/.widgetTintColor` (Task 1), `SplitFlapClockFace(...tintColor:fontName:isMonospacedSystemFont:)`, `SplitFlapDigit(...tintColor:fontName:isMonospacedSystemFont:)`, `WidgetGlassBackground(...tintColor:)` (Task 3).
- Produces: the finished, user-visible feature — nothing downstream depends on this task.

- [ ] **Step 1: `OverlayContentView.swift` — wire the main clock face and glass background**

Change:

```swift
    var body: some View {
        VStack(spacing: Self.dateSpacing(scale: settings.overlaySize.scale)) {
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: effectiveScale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                glassCard: true
            )

            if settings.showDateOnOverlay {
                DateFlapRow(date: timeProvider.tick.date, scale: effectiveScale, isDark: colorScheme == .dark, glassCard: true)
            }
        }
        .padding(Self.padding(scale: settings.overlaySize.scale))
        // Center explicitly instead of relying on the hosting window's
        // frame to match this content's natural size exactly — any drift
        // between the analytic `windowSize()` estimate and SwiftUI's real
        // layout (e.g. worst-case weekday width vs. today's actual
        // weekday) otherwise pins content to the window's top-left corner
        // instead of centering it, producing lopsided margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen))
        .preferredColorScheme(settings.theme.colorScheme)
    }
```

to:

```swift
    private var effectiveTint: Color? {
        settings.widgetTintEnabled ? settings.widgetTintColor : nil
    }

    var body: some View {
        VStack(spacing: Self.dateSpacing(scale: settings.overlaySize.scale)) {
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: effectiveScale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                glassCard: true,
                tintColor: effectiveTint,
                fontName: settings.widgetFont.postscriptName,
                isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem
            )

            if settings.showDateOnOverlay {
                DateFlapRow(date: timeProvider.tick.date, scale: effectiveScale, isDark: colorScheme == .dark, glassCard: true, tintColor: effectiveTint, fontName: settings.widgetFont.postscriptName, isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem)
            }
        }
        .padding(Self.padding(scale: settings.overlaySize.scale))
        // Center explicitly instead of relying on the hosting window's
        // frame to match this content's natural size exactly — any drift
        // between the analytic `windowSize()` estimate and SwiftUI's real
        // layout (e.g. worst-case weekday width vs. today's actual
        // weekday) otherwise pins content to the window's top-left corner
        // instead of centering it, producing lopsided margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen, tintColor: effectiveTint))
        .preferredColorScheme(settings.theme.colorScheme)
    }
```

- [ ] **Step 2: `OverlayContentView.swift` — thread through `DateFlapRow`**

Change:

```swift
private struct DateFlapRow: View {
    let date: Date
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false
```

to:

```swift
private struct DateFlapRow: View {
    let date: Date
    let scale: CGFloat
    let isDark: Bool
    var glassCard: Bool = false
    var tintColor: Color? = nil
    var fontName: String? = nil
    var isMonospacedSystemFont: Bool = false
```

Change:

```swift
    var body: some View {
        VStack(spacing: rowGap) {
            HStack(spacing: digitGap) {
                ForEach(Array(weekdayCharacters.enumerated()), id: \.offset) { _, character in
                    SplitFlapDigit(
                        value: character,
                        cardSize: cardSize,
                        isDark: isDark,
                        compact: false,
                        textColor: weekdayColor,
                        glassCard: glassCard
                    )
                }
            }

            HStack(spacing: groupGap) {
                ForEach(Array(dateGroups.enumerated()), id: \.offset) { _, group in
                    HStack(spacing: digitGap) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                            SplitFlapDigit(
                                value: character,
                                cardSize: cardSize,
                                isDark: isDark,
                                compact: false,
                                glassCard: glassCard
                            )
                        }
                    }
                }
            }
        }
    }
```

to:

```swift
    var body: some View {
        VStack(spacing: rowGap) {
            HStack(spacing: digitGap) {
                ForEach(Array(weekdayCharacters.enumerated()), id: \.offset) { _, character in
                    SplitFlapDigit(
                        value: character,
                        cardSize: cardSize,
                        isDark: isDark,
                        compact: false,
                        textColor: weekdayColor,
                        glassCard: glassCard,
                        tintColor: tintColor,
                        fontName: fontName,
                        isMonospacedSystemFont: isMonospacedSystemFont
                    )
                }
            }

            HStack(spacing: groupGap) {
                ForEach(Array(dateGroups.enumerated()), id: \.offset) { _, group in
                    HStack(spacing: digitGap) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                            SplitFlapDigit(
                                value: character,
                                cardSize: cardSize,
                                isDark: isDark,
                                compact: false,
                                glassCard: glassCard,
                                tintColor: tintColor,
                                fontName: fontName,
                                isMonospacedSystemFont: isMonospacedSystemFont
                            )
                        }
                    }
                }
            }
        }
    }
```

(`weekdayColor` — the Sunday-red `NSColor?` — stays exactly as-is; `SplitFlapDigit`'s `effectiveTextColor` from Task 3 Step 3 already makes `tintColor` win over `textColor` when both are present.)

- [ ] **Step 3: `MenuBarClockView.swift` — wire tint/font**

Change:

```swift
    var body: some View {
        SplitFlapClockFace(tick: timeProvider.tick, scale: 1, compact: true, meridiemStyle: settings.meridiemStyle, timeFormat: settings.timeFormat)
            .preferredColorScheme(settings.theme.colorScheme)
    }
```

to:

```swift
    var body: some View {
        SplitFlapClockFace(
            tick: timeProvider.tick,
            scale: 1,
            compact: true,
            meridiemStyle: settings.meridiemStyle,
            timeFormat: settings.timeFormat,
            tintColor: settings.widgetTintEnabled ? settings.widgetTintColor : nil,
            fontName: settings.widgetFont.postscriptName,
            isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem
        )
        .preferredColorScheme(settings.theme.colorScheme)
    }
```

- [ ] **Step 4: `SecondClockMenuBarView.swift` — wire tint/font**

Change:

```swift
    var body: some View {
        SplitFlapClockFace(tick: tick, scale: 1, compact: true, meridiemStyle: settings.meridiemStyle, timeFormat: settings.timeFormat)
            .preferredColorScheme(settings.theme.colorScheme)
    }
```

to:

```swift
    var body: some View {
        SplitFlapClockFace(
            tick: tick,
            scale: 1,
            compact: true,
            meridiemStyle: settings.meridiemStyle,
            timeFormat: settings.timeFormat,
            tintColor: settings.widgetTintEnabled ? settings.widgetTintColor : nil,
            fontName: settings.widgetFont.postscriptName,
            isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem
        )
        .preferredColorScheme(settings.theme.colorScheme)
    }
```

- [ ] **Step 5: `PopoverClockView.swift` — wire tint/font**

Change:

```swift
            SplitFlapClockFace(tick: timeProvider.tick, scale: Self.clockScale, compact: false, showPedestal: false, meridiemStyle: settings.meridiemStyle, timeFormat: settings.timeFormat, glassCard: true, showOwnGlassPanel: false)
```

to:

```swift
            SplitFlapClockFace(
                tick: timeProvider.tick,
                scale: Self.clockScale,
                compact: false,
                showPedestal: false,
                meridiemStyle: settings.meridiemStyle,
                timeFormat: settings.timeFormat,
                glassCard: true,
                showOwnGlassPanel: false,
                tintColor: settings.widgetTintEnabled ? settings.widgetTintColor : nil,
                fontName: settings.widgetFont.postscriptName,
                isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem
            )
```

`CalendarMonthView()` on the next line is NOT touched — out of scope per the design.

- [ ] **Step 6: `SettingsView.swift` — grow the Appearance tab window size**

Change:

```swift
    var windowSize: CGSize {
        switch self {
        case .general: return CGSize(width: 430, height: 220)
        case .appearance: return CGSize(width: 470, height: 300)
        case .desktopClock: return CGSize(width: 470, height: 305)
        case .secondClock: return CGSize(width: 470, height: 285)
        }
    }
```

to:

```swift
    var windowSize: CGSize {
        switch self {
        case .general: return CGSize(width: 430, height: 220)
        case .appearance: return CGSize(width: 470, height: 420)
        case .desktopClock: return CGSize(width: 470, height: 305)
        case .secondClock: return CGSize(width: 470, height: 285)
        }
    }
```

- [ ] **Step 7: `SettingsView.swift` — add Tint and Font cards to the Appearance tab**

Change:

```swift
            settingsCard("Glass") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Popover glass effect")
                    HStack(spacing: 10) {
                        Text("Solid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.popoverGlassiness, in: 0...1)
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .desktopClock:
```

to:

```swift
            settingsCard("Glass") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Popover glass effect")
                    HStack(spacing: 10) {
                        Text("Solid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.popoverGlassiness, in: 0...1)
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsCard("Tint") {
                Toggle("Use custom tint", isOn: $settings.widgetTintEnabled)
                if settings.widgetTintEnabled {
                    ColorPicker("Tint color", selection: $settings.widgetTintColor)
                }
            }

            settingsCard("Font") {
                Picker("Font", selection: $settings.widgetFont) {
                    ForEach(WidgetFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
                .pickerStyle(.menu)
            }
        case .desktopClock:
```

- [ ] **Step 8: Build**

```bash
cd /Users/rajeevranjan/ClaudeCode/Clock
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Launch and visually verify**

```bash
open -n /Users/rajeevranjan/Library/Developer/Xcode/DerivedData/FlipClock-*/Build/Products/Debug/FlipClock.app
```

Open Settings → Appearance tab. Confirm:
- "Tint" card shows a toggle; enabling it reveals a native color-well control.
- "Font" card shows a dropdown with all 6 font names.
- Enabling tint with a distinct color (e.g. red) changes the digit ink, hinge lines, separator dots, and the frosted card tone on the desktop widget, popover, AND both menu bar clocks (enable "Second Clock" in settings to check the second one too) — all to that same color family, consistently.
- Cycling through each font visibly changes the digit typeface (e.g. Courier looks distinctly different from SF Mono or Helvetica Condensed) on all three surfaces.
- Trigger a flip (wait for the seconds digit to tick) with tint enabled — the animating flap must look identical to the resting cards, no flash (this is the guarantee Task 3's `frostedCard(isDark:tint:)`/`textColor` threading through `FlipCardLayer` exists to preserve).
- Disable tint — clock reverts to the original black/white-on-glass look immediately.
- Fill-screen mode and drag (from the previous fixes) still work with tint/font applied.

- [ ] **Step 10: Commit**

```bash
git add FlipClock/DesktopOverlay/OverlayContentView.swift FlipClock/MenuBar/MenuBarClockView.swift FlipClock/MenuBar/SecondClockMenuBarView.swift FlipClock/Popover/PopoverClockView.swift FlipClock/Settings/SettingsView.swift
git commit -m "feat: wire tint and font settings into all three clock surfaces"
```

---

## Self-Review Notes

- **Spec coverage:** `WidgetFont` enum + persistence → Task 1. Tint-aware `FlapColors` + font-aware `DigitFaceRenderer` → Task 2. Threading through `SplitFlapDigit`/`FlipCardLayer`/`SplitFlapPairView`/`SplitFlapClockFace`/`WidgetGlassBackground` → Task 3. All five call sites (desktop overlay, menu bar ×2, popover) + Settings UI → Task 4. Tint-wins-over-Sunday-red priority rule → Task 3 Step 3 (`effectiveTextColor`). Scope boundary (`CalendarMonthView` untouched) → explicitly called out in Task 4 Step 5.
- **Placeholder scan:** none — every step has complete, exact code, no TODOs.
- **Type consistency:** `tintColor: Color?`, `fontName: String?`, `isMonospacedSystemFont: Bool` use identical names and types at every layer (`SplitFlapClockFace` → `SplitFlapPairView` → `SplitFlapDigit` → `FlipCardLayer`/`DigitFaceRenderer`). `WidgetFont.postscriptName`/`.isMonospacedSystem` (Task 1) are read only in Task 4's call sites, matching the parameter names `fontName`/`isMonospacedSystemFont` used throughout Tasks 2-3. `FlapColors`' `tint: Color? = nil` parameter name and default are identical across all three modified functions.
