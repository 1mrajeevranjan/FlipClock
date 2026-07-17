# DesktopOverlay HIG widget compliance — design

## Context

Apple's [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets) was checked against `DesktopOverlay/` (see `architecture-map.md` for the full module map). DesktopOverlay is a custom `NSPanel`-hosted SwiftUI widget, not a real WidgetKit extension, so some HIG concepts (accessory sizes, mounting styles, container-relative shape API) don't literally apply. What does apply and is already satisfied:

- Full-color rendering only, no accent-tint mode — matches Mac Desktop's supported rendering modes (Full-color + Vibrant, no Accented).
- Single clear purpose, dynamic/timely content, no logo/brand clutter, "Desktop and Notification Center" size support (small/medium/large/extra-large all present via `OverlaySize` + `fillScreen`).

Two concrete, measurable deviations remain, both in `DesktopOverlay/WidgetGlassBackground.swift` and `DesktopOverlay/OverlayContentView.swift`:

1. **Corner radius** is a flat `34pt` constant (`WidgetGlassBackground.cornerRadius`), forced to `0` only in `fillScreen` mode. HIG expects radius to scale with the container rather than stay fixed.
2. **Padding** is a flat `22pt` constant (`OverlayContentView.padding`, plus `dateSpacing = 10`), identical at every `OverlaySize`. HIG's standard margin is `16pt`, with an `11pt` floor for tight groupings — the current value doesn't shrink at the `0.325x` "half" size.

One deviation is **not fixed by design**: HIG prefers live `Text` with the system font, ≥11pt, never rasterized. Every glyph in FlipClock (digits, weekday, AM/PM) is a rasterized bitmap card via `DigitFaceRenderer` — this is the split-flap mechanism itself, the product's core identity. Out of scope; noted here so it isn't mistaken for an oversight.

Additionally, in-scope: current elevation is binary (`NSWindow.hasShadow` on/off, in `OverlayWindowController.swift`), not size-proportional like a real system widget's soft elevation.

## Design

All three fixes are formulas driven by the existing `overlaySize.scale` (0.325 / 0.65 / 1.3 / 1.95), replacing flat constants in place — no new types, no new settings, no new files.

### 1. Corner radius (`WidgetGlassBackground.swift`)

```swift
static func cornerRadius(scale: CGFloat) -> CGFloat {
    (34 * scale).clamped(to: 14...40)
}
```

- At `scale = 0.65` (`.full`, the actual default `OverlaySize`): `clamp(22.1)` → `22.1pt` — down from the old flat `34pt`, a deliberate change so radius tracks widget size instead of staying fixed.
- At `scale = 0.325` (half): `clamp(11.05)` → `14pt` floor.
- At `scale = 1.95` (triple): `clamp(66.3)` → `40pt` ceiling.
- `scale = 1` is the formula's anchor point (`34 * 1 = 34`, matching the old constant exactly) — no `OverlaySize` case actually reaches it; don't read it as "the default."
- `fillScreen` mode keeps forcing `0` (edge-to-edge), unchanged.

### 2. Padding (`OverlayContentView.swift`)

```swift
static func padding(scale: CGFloat) -> CGFloat {
    (16 * scale).clamped(to: 11...22)
}
static func dateSpacing(scale: CGFloat) -> CGFloat {
    (10 * scale).clamped(to: 7...14)
}
```

- Base value now `16pt` (HIG standard margin) instead of an arbitrary `22`.
- At `scale = 0.65` (`.full`, the actual default `OverlaySize`): `clamp(10.4)` → `11pt` floor — down from the old flat `22pt`, a deliberate move toward HIG's standard margin rather than preserving today's look. (`scale = 1` would give the un-clamped `16pt`, but no `OverlaySize` case reaches `scale = 1`.)
- Floor `11pt` matches HIG's own tight-margin fallback; never goes below it even at `0.325x`.
- `dateSpacing` follows the same shape at roughly 2/3 the padding value, floor `7pt`/ceiling `14pt`.
- `windowSize(...)`'s analytic sizing math already multiplies `padding * 2` — no change to that formula, just to what value flows in.

### 3. Shadow / elevation (`WidgetGlassBackground.swift`)

Add a SwiftUI `.shadow(...)` on the glass panel's `RoundedRectangle`, layered under the existing `NSWindow.hasShadow` (unchanged, still native-window elevation on top):

```swift
.shadow(
    color: .black.opacity(0.18),
    radius: (12 * scale).clamped(to: 6...20),
    x: 0,
    y: (4 * scale).clamped(to: 2...8)
)
```

- Suppressed in `fillScreen` mode (no shadow on an edge-to-edge fill), same condition already used for `fullyClear`/`cornerRadius: 0`.
- Gives soft, size-proportional elevation instead of one fixed OS-default shadow at every size.

### Implementation notes

- A small `Comparable.clamped(to:)` helper doesn't currently exist in the codebase — add it once (private, in `WidgetGlassBackground.swift` or wherever it's first needed) rather than inlining `min(max(...))` three times.
- `WidgetGlassBackground` currently takes `cornerRadius` as a stored default-valued property (`Self.cornerRadius`); it changes to take `scale` (or the already-computed radius) as a parameter from `OverlayContentView`, which already has `settings.overlaySize.scale` and `settings.fillScreen` in scope at the call site (`OverlayContentView.swift:63`).
- No changes to `OverlayWindowController.swift`'s `hasShadow` on/off logic — the new SwiftUI shadow is additive, not a replacement.

## Testing

No test target exists in this project (per `CLAUDE.md`). Verification is visual: build, run, and screenshot the desktop overlay at each `OverlaySize` (half/full/double/triple) and in `fillScreen` mode, confirming radius/padding/shadow scale sensibly and `fillScreen` still renders edge-to-edge with no shadow.
