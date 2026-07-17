# DesktopOverlay HIG Widget Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace DesktopOverlay's flat corner-radius/padding constants with size-scaled formulas per Apple's Widget HIG, and add proportional shadow elevation.

**Architecture:** No structural change. `WidgetGlassBackground.swift` and `OverlayContentView.swift` keep their existing shape — three magic-number constants (`cornerRadius: CGFloat = 34`, `padding: CGFloat = 22`, `dateSpacing: CGFloat = 10`) become functions of `settings.overlaySize.scale`, clamped to sane ranges, plus a new size-proportional `.shadow(...)` on the glass panel.

**Tech Stack:** Swift 5.0, SwiftUI + AppKit, no external dependencies, no test target (project has none — see `CLAUDE.md`).

## Global Constraints

- Corner radius: `(34 * scale).clamped(to: 14...40)` — unchanged at `scale = 1` (default `full` size).
- Padding: `(16 * scale).clamped(to: 11...22)` — HIG's 16pt standard margin as the base value (was `22` flat).
- Date spacing: `(10 * scale).clamped(to: 7...14)`.
- Shadow: `.shadow(color: .black.opacity(0.18), radius: (12 * scale).clamped(to: 6...20), x: 0, y: (4 * scale).clamped(to: 2...8))`, layered under the existing `NSWindow.hasShadow` (unchanged), suppressed when `fullyClear`/`fillScreen`.
- `scale` in every formula above is `settings.overlaySize.scale` (0.325/0.65/1.3/1.95) — never `effectiveScale` (which adds the `fillScreen` 1.6x multiplier); `fillScreen` already bypasses `WidgetGlassBackground`'s rounded/shadowed path entirely via `fullyClear`.
- No new files, no new `AppSettings` properties, no new abstractions beyond a single `Comparable.clamped(to:)` helper.
- Verification is build + visual, not unit tests (no test target exists): `xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build` must report `** BUILD SUCCEEDED **`, then launch and screenshot the overlay.

---

### Task 1: Scale-aware corner radius + shadow in `WidgetGlassBackground`

**Files:**
- Modify: `FlipClock/DesktopOverlay/WidgetGlassBackground.swift` (whole file — see below)
- Modify: `FlipClock/DesktopOverlay/OverlayContentView.swift:63` (call site)

**Interfaces:**
- Produces: `WidgetGlassBackground(scale: CGFloat = 1, fullyClear: Bool = false)` (replaces old `WidgetGlassBackground(cornerRadius: CGFloat, fullyClear: Bool)` init signature), `WidgetGlassBackground.cornerRadius(scale: CGFloat) -> CGFloat` (static), and a file-visible `extension Comparable { func clamped(to range: ClosedRange<Self>) -> Self }` that Task 2 also relies on.
- Consumes: nothing from earlier tasks (this is the first task).

- [ ] **Step 1: Replace `WidgetGlassBackground.swift` in full**

```swift
import SwiftUI
import AppKit

/// Frosted-glass container matching the default macOS desktop widget look
/// (Calendar/Weather widgets in Notification Center): a behind-window
/// vibrant blur clipped to a large rounded rect, with a faint inner
/// highlight stroke, a size-proportional soft shadow, and the window's own
/// drop shadow doing the rest.
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

    /// `34pt` at `scale = 1` (unchanged from the previous flat constant),
    /// clamped to `14...40` so it never vanishes at the smallest widget size
    /// or balloons past a sane maximum at the largest.
    static func cornerRadius(scale: CGFloat) -> CGFloat {
        (34 * scale).clamped(to: 14...40)
    }

    private var cornerRadius: CGFloat {
        fullyClear ? 0 : Self.cornerRadius(scale: scale)
    }

    var body: some View {
        if fullyClear {
            Color.clear
        } else {
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
        }
    }
}

/// Bridges `NSVisualEffectView` with `.behindWindow` blending so the blur
/// samples the desktop wallpaper/icons beneath the overlay window, not just
/// this view's own SwiftUI content — SwiftUI's `Material` types only blend
/// with what's drawn inside the same view hierarchy, which isn't enough
/// here since the window itself is transparent over the desktop.
///
/// `.underWindowBackground` is the material that actually tints with the
/// wallpaper hue behind it (the "colorful" glass Calendar/Weather widgets
/// show) — `.hudWindow` reads as flat neutral gray regardless of what's
/// behind the window, which is why the first pass looked wrong.
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Comparable {
    /// Constrains `self` to `range`, used to keep size-scaled widget metrics
    /// (corner radius, padding, shadow) within sane bounds at the smallest
    /// and largest `OverlaySize` scales.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 2: Update the call site in `OverlayContentView.swift`**

Change line 63 from:

```swift
        .background(WidgetGlassBackground(cornerRadius: settings.fillScreen ? 0 : WidgetGlassBackground.cornerRadius, fullyClear: settings.fillScreen))
```

to:

```swift
        .background(WidgetGlassBackground(scale: settings.overlaySize.scale, fullyClear: settings.fillScreen))
```

- [ ] **Step 3: Build**

Run from the repo root (`/Users/rajeevranjan/ClaudeCode/Clock`):

```bash
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: last line of output is `** BUILD SUCCEEDED **`. If it fails, read the actual `xcodebuild` error (not editor/SourceKit diagnostics — this codebase has shown stale ones before, per `CLAUDE.md`) and fix before continuing.

- [ ] **Step 4: Launch and visually verify**

```bash
open -n /Users/rajeevranjan/Library/Developer/Xcode/DerivedData/FlipClock-*/Build/Products/Debug/FlipClock.app
```

Open Settings → Desktop Clock tab, enable "Show on Desktop", and cycle through each `OverlaySize` (half/full/double/triple) plus toggling "Fill Screen" on and off. For each, take a screenshot (`screencapture -x <path>`) and confirm:
- Corner radius visibly shrinks at `half` and grows at `triple` relative to `full` (unchanged look at `full`).
- A soft shadow is visible under the glass panel at every non-fill-screen size, subtler at `half` than at `triple`.
- `fillScreen` mode still renders edge-to-edge with square corners and no shadow (unchanged from before).

- [ ] **Step 5: Commit**

```bash
git add FlipClock/DesktopOverlay/WidgetGlassBackground.swift FlipClock/DesktopOverlay/OverlayContentView.swift
git commit -m "feat: scale DesktopOverlay corner radius and add proportional shadow"
```

---

### Task 2: Scale-aware padding and date spacing in `OverlayContentView`

**Files:**
- Modify: `FlipClock/DesktopOverlay/OverlayContentView.swift:9-10` (constants), `:21-27` (`windowSize`), `:40` (`VStack` spacing), `:55` (`.padding`)

**Interfaces:**
- Consumes: `Comparable.clamped(to:)` from Task 1 (`FlipClock/DesktopOverlay/WidgetGlassBackground.swift`).
- Produces: `OverlayContentView.padding(scale: CGFloat) -> CGFloat` (static), `OverlayContentView.dateSpacing(scale: CGFloat) -> CGFloat` (static) — replace the old `static let padding`/`static let dateSpacing`. No other file references these constants (confirmed: only `WidgetGlassBackground.swift`'s old `cornerRadius` and these two were the flat constants in DesktopOverlay).

- [ ] **Step 1: Replace the constants (lines 9-10)**

Change:

```swift
    static let padding: CGFloat = 22
    static let dateSpacing: CGFloat = 10
```

to:

```swift
    /// HIG's standard widget margin is 16pt; scaling it by `overlaySize`
    /// and clamping to `11...22` keeps the smallest widget from crowding
    /// its edges while never exceeding today's default-size look.
    static func padding(scale: CGFloat) -> CGFloat {
        (16 * scale).clamped(to: 11...22)
    }

    static func dateSpacing(scale: CGFloat) -> CGFloat {
        (10 * scale).clamped(to: 7...14)
    }
```

- [ ] **Step 2: Update `windowSize(scale:showDate:showMeridiem:)` (lines 21-27)**

Change:

```swift
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateSize = showDate ? dateRowSize(scale: scale) : .zero
        let width = max(face.width, dateSize.width) + padding * 2
        let height = face.height + (showDate ? dateSpacing + dateSize.height : 0) + padding * 2
        return CGSize(width: width, height: height)
    }
```

to:

```swift
    static func windowSize(scale: CGFloat, showDate: Bool, showMeridiem: Bool) -> CGSize {
        let face = SplitFlapClockFace.idealSize(scale: scale, compact: false, showPedestal: false, showMeridiem: showMeridiem)
        let dateSize = showDate ? dateRowSize(scale: scale) : .zero
        let contentPadding = padding(scale: scale)
        let width = max(face.width, dateSize.width) + contentPadding * 2
        let height = face.height + (showDate ? dateSpacing(scale: scale) + dateSize.height : 0) + contentPadding * 2
        return CGSize(width: width, height: height)
    }
```

- [ ] **Step 3: Update the body (lines 40 and 55)**

Change line 40 from:

```swift
        VStack(spacing: Self.dateSpacing) {
```

to:

```swift
        VStack(spacing: Self.dateSpacing(scale: settings.overlaySize.scale)) {
```

Change line 55 from:

```swift
        .padding(Self.padding)
```

to:

```swift
        .padding(Self.padding(scale: settings.overlaySize.scale))
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Launch and visually verify**

```bash
open -n /Users/rajeevranjan/Library/Developer/Xcode/DerivedData/FlipClock-*/Build/Products/Debug/FlipClock.app
```

Cycle through each `OverlaySize` again with "Show Date" toggled on. Confirm:
- The gap between the glass panel's edge and the clock face visibly shrinks at `half` and is roughly unchanged at `full` (16pt margin vs. the old 22pt — a small, deliberate tightening).
- The window doesn't clip the clock face or date row at any size (the analytic `windowSize` still matches what SwiftUI actually lays out — if it doesn't, content will look off-center or the window edge will crowd/clip it).
- `fillScreen` mode is unaffected (it doesn't route through `padding`/`dateSpacing` differently than before — same call, just scaled values).

- [ ] **Step 6: Commit**

```bash
git add FlipClock/DesktopOverlay/OverlayContentView.swift
git commit -m "feat: scale DesktopOverlay padding and date spacing to HIG margin standard"
```

---

## Self-Review Notes

- **Spec coverage:** corner radius formula → Task 1; padding/date-spacing formula → Task 2; shadow → Task 1 (bundled with corner radius since both live in `WidgetGlassBackground` and both need `scale`). All three formulas from the spec's "Design" section are implemented verbatim.
- **Placeholder scan:** none — every step has complete, exact code.
- **Type consistency:** `WidgetGlassBackground` changes its init from `(cornerRadius: CGFloat, fullyClear: Bool)` to `(scale: CGFloat, fullyClear: Bool)` in Task 1, Step 1-2 together (both the type and its one call site updated in the same task, so there's no intermediate broken state). `Comparable.clamped(to:)` is defined once in Task 1 and reused as-is (same name, same signature) in Task 2 — no divergent helper names.
