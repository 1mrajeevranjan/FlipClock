# FlipClock Architecture Map

Menu bar macOS app rendering a split-flap clock across three surfaces (menu bar status item, popover with calendar, floating desktop overlay), all driven by one shared `TimeProvider` and one shared rendering engine (`SplitFlapClockFace` and friends).

## App/
Composition root only.

| File | Responsibility |
|---|---|
| `App/FlipClockApp.swift` | `@main` entry; `Settings` scene wrapping `SettingsView` |
| `App/AppDelegate.swift` | Owns shared `TimeProvider`/`AppSettings`, constructs all surface controllers |

## TimeEngine/
Pure model layer, no views. Leaf module — everything else depends on it.

| File | Responsibility |
|---|---|
| `TimeProvider.swift` | `@Observable`, 1s timer on `.common` run-loop mode, resyncs on wake |
| `ClockTick.swift` | Hour/min/sec/AMPM snapshot; derives other-timezone ticks from same `Date` |
| `DigitDelta.swift` | Diffs two ticks so unrelated digits don't animate |

## FlipClock/ (shared rendering engine)
Reusable split-flap primitives used identically by MenuBar, Popover, DesktopOverlay.

| File | Responsibility |
|---|---|
| `SplitFlapClockFace.swift` | Full HH:MM:SS(+AMPM) face; `scale`/`compact`/`showPedestal`/`glassCard` params; `idealSize(...)` for analytic window sizing |
| `SplitFlapPairView.swift` | Two digit cards (tens+ones) with gap |
| `SplitFlapDigit.swift` | One flap card: static halves + hinge + animating flap; owns `glassCard`/`showOwnGlassPanel` |
| `FlipCardLayer.swift` | `NSViewRepresentable` driving the CALayer 3D flip animation |
| `DigitFaceRenderer.swift` | Rasterizes/caches digit+label bitmaps via CoreText |
| `FlapColors.swift` | Centralized color tokens |

## Settings/
Preferences store + SwiftUI settings UI.

| File | Responsibility |
|---|---|
| `AppSettings.swift` | `ObservableObject`, UserDefaults-backed; `AppTheme`, `OverlaySize` (half/full/double/triple → scale 0.325/0.65/1.3/1.95), `TimeFormat`, `MeridiemStyle` |
| `SettingsView.swift` | Tabbed settings UI; "Desktop Clock" tab controls overlay |
| `SettingsWindowController.swift` | Self-managed `NSWindow` host (works around `LSUIElement` `Settings` scene issues) |

**Key fact:** `OverlaySize` is the only sizing lever exposed today. No independent corner-radius/padding/material control — hardcoded in DesktopOverlay.

## MenuBar/ (brief)
`StatusItemController` (owns `NSStatusItem`, opens popover), `MenuBarClockView` (compact face), `SecondClockStatusItemController`/`SecondClockMenuBarView` (optional second timezone item).

## Popover/ (brief)
`PopoverClockView` (clock + `DateHeaderView` + `CalendarMonthView`, `showOwnGlassPanel: false`), `VibrantHostingController` (makes `NSVisualEffectView` the top-level content view to match `NSPopover` chrome), `CalendarMonthView`, `DateHeaderView`.

## DesktopOverlay/ (deep dive — the widget being redesigned)

Floating, borderless `NSPanel` pinned near desktop-icon level, optional full-screen "fill screen" mode and DVD-bounce "float across screen" mode.

**Composition:**
```
OverlayWindow (NSPanel subclass)
  └─ NSHostingController(OverlayContentView)   [wired in OverlayWindowController]
       └─ OverlayContentView (SwiftUI root)
            ├─ SplitFlapClockFace (shared)         — HH:MM:SS(+AMPM)
            ├─ DateFlapRow (private)                — optional weekday+date flap row
            └─ .background(WidgetGlassBackground)   — frosted glass panel
```

| File | Responsibility |
|---|---|
| `OverlayWindow.swift` | `NSPanel` subclass: borderless, non-activating, transparent-backed, shadowed, joins all Spaces, draggable by background |
| `OverlayWindowController.swift` | Creates window, wires SwiftUI content, reacts to all settings changes, drives the float-drift timer |
| `OverlayContentView.swift` | SwiftUI root: clock + optional date row, fixed padding, analytic `windowSize(...)`; defines private `DateFlapRow` |
| `WidgetGlassBackground.swift` | `RoundedRectangle` clip + `NSVisualEffectView` (`.behindWindow`, `.underWindowBackground`) for true desktop-sampling blur + white stroke highlight; collapses to `Color.clear` in full-screen mode |

**Settings driving overlay appearance** (all in `AppSettings`):
`showDesktopOverlay`, `overlaySize` (only size control), `showDateOnOverlay`, `timeFormat`, `meridiemStyle`, `theme`, `floatAcrossScreen` (mutually exclusive with `fillScreen`), `fillScreen` (covers `NSScreen.main`, disables drag/shadow, corner radius→0, `1.6x` extra scale). No position setting — default top-right anchor, then window-frame-autosave or wherever float-drift left it (unpersisted).

**Current hardcoded visual constants (the actual redesign surface):**
- **Corner radius:** `WidgetGlassBackground.cornerRadius = 34` (flat constant, forced to `0` in full-screen). Not derived from size class.
- **Padding:** `OverlayContentView.padding = 22` (flat constant, same at every `OverlaySize`); `dateSpacing = 10`.
- **Shadow:** delegated to `NSWindow.hasShadow` (native AppKit shadow), on/off only — no tuned radius/offset/opacity in SwiftUI.
- **Materials/blur:** `NSVisualEffectView(.behindWindow, .underWindowBackground)` at `.opacity(0.22)`, `Color.white.opacity(0.12)` 0.75pt stroke. Independent from each digit's own per-card `.hudWindow` glass panel (`showOwnGlassPanel` defaults `true` here, unlike Popover).
- **Typography:** no live `Text`/system font anywhere — every character (digits, weekday, AM/PM) is rasterized into a bitmap card via `DigitFaceRenderer` (`NSFont.systemFont(size: fullSize.height*0.78, weight: .heavy)`, shrink-to-fit). This is core to the split-flap product identity, not an oversight.

**Cross-module dependencies:** TimeEngine (`TimeProvider`/`ClockTick`), Settings (`AppSettings` + its enums), shared FlipClock/ rendering (`SplitFlapClockFace`, `SplitFlapDigit`, `DigitFaceRenderer`, `FlapColors`, `FlipCardLayer`). No dependency on MenuBar/Popover in either direction.
