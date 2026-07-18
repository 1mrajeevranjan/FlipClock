# Widget tint + font customization — design

## Context

Feature request: let the user pick a custom accent tint (matching Apple's Widget HIG "tinted" appearance mode) and a font, applied across all three clock surfaces — desktop overlay widget, menu bar popover, and the compact menu bar clock itself (including the optional second-timezone menu bar clock).

All three surfaces already render through one shared engine (`SplitFlapClockFace` → `SplitFlapPairView`/`SplitFlapDigit` → `DigitFaceRenderer`/`FlipCardLayer`/`WidgetGlassBackground`, per `architecture-map.md`), so the design threads two new optional parameters down that existing chain rather than building per-surface logic.

## Settings (`AppSettings.swift`)

```swift
enum WidgetFont: String, CaseIterable, Identifiable {
    case system, sfMono, menlo, avenirNext, helveticaCondensed, courier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .sfMono: "SF Mono"
        case .menlo: "Menlo"
        case .avenirNext: "Avenir Next"
        case .helveticaCondensed: "Helvetica Condensed"
        case .courier: "Courier"
        }
    }

    /// PostScript name for `NSFont(name:size:)`. `nil` means either the
    /// plain system font (`.system`) or the monospaced system font
    /// (`.sfMono`, resolved via `NSFont.monospacedSystemFont` since that's
    /// the correct API for it, not a PostScript name lookup) —
    /// `isMonospacedSystem` disambiguates the two `nil` cases.
    var postscriptName: String? {
        switch self {
        case .system, .sfMono: nil
        case .menlo: "Menlo-Bold"
        case .avenirNext: "AvenirNext-Heavy"
        case .helveticaCondensed: "HelveticaNeue-CondensedBlack"
        case .courier: "Courier-Bold"
        }
    }

    var isMonospacedSystem: Bool { self == .sfMono }
}
```

All six are bundled system fonts/APIs — no missing-weight risk. `DigitFaceRenderer` falls back to the plain system font if `NSFont(name:)` ever returns nil (defensive, shouldn't happen for this list).

New published properties, following the exact existing `Keys`/`init` pattern:

```swift
@Published var widgetFont: WidgetFont { didSet { ... } }          // default .system
@Published var widgetTintEnabled: Bool { didSet { ... } }         // default false
@Published var widgetTintColor: Color { didSet { ... } }          // default #007AFF, persisted as hex string
```

`Color` isn't directly `UserDefaults`-storable; add a small private `Color(hex:)` / `.hexString` bridge at the bottom of `AppSettings.swift` (RGB only, no alpha — tint is always applied at a fixed opacity by the renderer, not by the stored color itself). Requires adding `import AppKit` to `AppSettings.swift` for the `NSColor` bridging.

## Rendering changes

### `FlapColors.swift`

Add an optional `tint: Color? = nil` parameter to the four affected token functions — default `nil` preserves every existing call site's behavior exactly:

```swift
static func leafHinge(isDark: Bool, tint: Color? = nil) -> Color {
    if let tint { return tint.opacity(0.4) }
    return isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.2)
}

static func frostedCard(isDark: Bool, tint: Color? = nil) -> Color {
    if let tint { return tint.opacity(0.3) }
    return isDark ? Color(red: 0.22, green: 0.25, blue: 0.30) : Color(red: 0.86, green: 0.89, blue: 0.93)
}

static func separatorDot(isDark: Bool, tint: Color? = nil) -> Color {
    if let tint { return tint.opacity(0.85) }
    return isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.5)
}
```

`digit(isDark:)` is untouched — tint reaches digit ink through the *existing* `textColor: NSColor?` override already threaded through `SplitFlapDigit`/`DigitFaceRenderer` (currently only used for the Sunday-red weekday case), not a new parameter.

### `SplitFlapDigit.swift`

Add `var tintColor: Color? = nil`, `var fontName: String? = nil`, `var isMonospacedSystemFont: Bool = false`.

- Effective glyph color: `tintColor.map(NSColor.init) ?? textColor` (tint wins over the Sunday-red `textColor` override when both are present — confirmed with user) — passed as `textColor:` to `DigitFaceRenderer.halfFace(...)`.
- `fontName`/`isMonospacedSystemFont` passed straight through to `DigitFaceRenderer.halfFace(...)`.
- `DraggableColorView(color:)` uses `FlapColors.frostedCard(isDark: isDark, tint: tintColor)`.
- `HingeLine` gains a `tint: Color?` field, passed to `FlapColors.leafHinge(isDark:tint:)`.

### `FlipCardLayer.swift`

Add `var tintColor: Color? = nil`, `var fontName: String? = nil`, `var isMonospacedSystemFont: Bool = false`. Both `DigitFaceRenderer.halfFace(...)` calls (phase 1 and phase 2) gain:
- `fillColor: NSColor(FlapColors.frostedCard(isDark: isDark, tint: tintColor))` when `glassCard` (replaces the current bare `FlapColors.frostedCard(isDark: isDark)` call — same function, tint-aware now).
- `textColor: tintColor.map(NSColor.init)`, `fontName:`, `isMonospacedSystemFont:` passed through.

### `DigitFaceRenderer.swift`

`face`, `halfFace`, `render`, and `line(for:)` each gain `fontName: String? = nil, isMonospacedSystemFont: Bool = false` parameters. `SizeKey`/`HalfKey` gain a `fontIdentifier: String` field (`fontName ?? (isMonospacedSystemFont ? "sfmono" : "system")`) so the bitmap cache doesn't serve stale glyphs from a different font after the user switches — this is the one correctness-critical detail, easy to miss since the cache currently has no font dimension at all.

`line(for:)`'s font-resolution loop:

```swift
let font: NSFont
if isMonospacedSystemFont {
    font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy)
} else if let fontName, let named = NSFont(name: fontName, size: fontSize) {
    font = named
} else {
    font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
}
```

### `SplitFlapPairView.swift`, `SplitFlapClockFace.swift`

Both gain the same three passthrough params (`tintColor`, `fontName`, `isMonospacedSystemFont`), threaded to every `SplitFlapDigit`/`SplitFlapPairView` call inside. `SplitFlapClockFace`'s `separator(_:)` (the colon dots) uses `FlapColors.separatorDot(isDark: isDark, tint: tintColor)`.

### `WidgetGlassBackground.swift`

Add `var tintColor: Color? = nil`. In the non-`fullyClear` branch, add a translucent overlay when set:

```swift
.overlay {
    if let tintColor {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tintColor.opacity(0.18))
    }
}
```

### Call sites — where settings actually get read

- `OverlayContentView.swift`: `SplitFlapClockFace(...)` and `DateFlapRow`'s two digit loops get `tintColor: settings.widgetTintEnabled ? settings.widgetTintColor : nil, fontName: settings.widgetFont.postscriptName, isMonospacedSystemFont: settings.widgetFont.isMonospacedSystem`. `DateFlapRow`'s existing `weekdayColor` (Sunday-red) computation stays as-is — the priority rule (tint wins) is enforced inside `SplitFlapDigit`, not here. `WidgetGlassBackground(...)` call gets the same `tintColor` expression.
- `MenuBarClockView.swift`, `SecondClockMenuBarView.swift`: same three params on their `SplitFlapClockFace(...)` calls.
- `PopoverClockView.swift`: same three params on its `SplitFlapClockFace(...)` call. `CalendarMonthView` is explicitly untouched — it's calendar-grid UI chrome, not split-flap digits, out of scope.

## Settings UI (`SettingsView.swift`)

Two new cards in the `.appearance` tab, after the existing "Glass" card:

```swift
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
```

`ColorPicker` is SwiftUI's native color-well control — opens the system color panel, matching "full system color picker." `.pickerStyle(.menu)` (dropdown) instead of the `.segmented` style the other two-to-four-option pickers use, since six font options would cramp a segmented control.

`SettingsTab.appearance`'s `windowSize` grows from `CGSize(width: 470, height: 300)` to `CGSize(width: 470, height: 420)` to fit the two new cards.

## Testing

No test target exists in this project. Verification is visual: build, run, toggle tint on/off with a few different colors, cycle through all six fonts, and confirm the change shows correctly and consistently across all three surfaces (desktop widget, popover, menu bar clock) — including mid-flip (tint/font must look identical on the animating flap and the resting card, same as the existing frosted-card-consistency guarantee) and with the second-timezone menu bar clock enabled.
