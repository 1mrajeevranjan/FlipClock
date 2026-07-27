# FlipClock Architecture

Menu bar macOS app rendering a split-flap clock across three surfaces (menu bar status item, popover with calendar, floating desktop overlay), all driven by one shared `TimeProvider`, one shared rendering engine (`SplitFlapClockFace` and friends), and one shared `ReminderStore`.

Supersedes the earlier `architecture-map.md` — this is the current map.

## App/
Composition root only.

| File | Responsibility |
|---|---|
| `App/FlipClockApp.swift` | `@main` entry; `Settings` scene wrapping `SettingsView` |
| `App/AppDelegate.swift` | Owns shared `TimeProvider`/`AppSettings`/`ReminderStore`, constructs all surface controllers |

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
| `SplitFlapClockFace.swift` | Full HH:MM:SS(+AMPM) face; `scale`/`compact`/`showPedestal`/`glassCard`/`isDarkOverride` params; `idealSize(...)` for analytic window sizing |
| `SplitFlapPairView.swift` | Two digit cards (tens+ones) with gap |
| `SplitFlapDigit.swift` | One flap card: static halves + hinge + animating flap; owns `glassCard`/`showOwnGlassPanel` |
| `FlipCardLayer.swift` | `NSViewRepresentable` driving the CALayer 3D flip animation |
| `DigitFaceRenderer.swift` | Rasterizes/caches digit+label bitmaps via CoreText; also draws the sun/moon meridiem icon images (aspect-fit, half-card-aware) |
| `FlapColors.swift` | Centralized color tokens |
| `WidgetFont.swift` | Bundled decorative-font catalog (37 fonts under `Fonts/`), PostScript-name-based registration via `CTFontManagerRegisterFontsForURL` |

`isDarkOverride` on `SplitFlapClockFace` exists specifically for the menu bar reminder pulse — see Known Gotchas in `CLAUDE.md` for why `.preferredColorScheme()` alone isn't enough there.

## Settings/
Preferences store + SwiftUI settings UI.

| File | Responsibility |
|---|---|
| `AppSettings.swift` | `ObservableObject`, UserDefaults-backed. Enums: `AppTheme`, `OverlaySize` (half/full/double/triple → scale 0.325/0.65/1.3/1.95), `TimeFormat`, `MeridiemStyle` (text/icon — icon renders bundled sun.png/moon.png), `WidgetColorStyle` (full/monochrome) |
| `SettingsView.swift` | Tabbed settings UI (General / Appearance / Desktop Clock / Second Clock); each tab resizes the window instead of leaving blank space. Second Clock's "Show second clock" segmented control (Off/Menu Bar/Desktop Widget/Both) edits `AppSettings.secondClockDisplay`, a UI-only computed property over the two underlying `showSecondClock`/`showSecondClockOverlay` booleans |
| `SettingsWindowController.swift` | Self-managed `NSWindow` host (works around `LSUIElement` `Settings` scene issues); native title (flush with the traffic lights) shows the selected tab's name — `SettingsView` no longer draws its own duplicate heading below it |

**Persisted settings today:** `showDesktopOverlay`, `launchAtLogin`, `theme`, `overlaySize`, `meridiemStyle`, `showSecondClock`, `secondTimezoneID`, `showSecondClockOverlay`, `timeFormat`, `showDateOnOverlay`, `floatAcrossScreen`, `fillScreen`, `widgetFont`, `widgetColorStyle`.

## Reminders/
Shared reminder data + UI fragments, consumed by Popover, DesktopOverlay, and MenuBar.

| File | Responsibility |
|---|---|
| `Reminder.swift` | `Codable` model: `id`, `date` (day + precise time), `title`, `isAcknowledged` |
| `ReminderStore.swift` | `ObservableObject`, UserDefaults-JSON persisted. `dueTodayUnacknowledged`, `upcomingWithin24Hours`, `reminders(on:)`, `add/remove/acknowledge` |
| `AddReminderView.swift` | Popover form (title + "@ time" picker) triggered by double-clicking a calendar day |
| `ReminderBadge.swift` | Small pulsing dot (red = due today, orange = upcoming within 24h) — reused by the calendar day mark and the desktop widget's corner badge |
| `DueReminderBanner.swift` | "Due Today" list shown in the popover with a per-reminder acknowledge checkmark — this is what stops the menu bar pulse |

One `ReminderStore` instance is created in `AppDelegate` and passed by reference everywhere; all three surfaces always agree on what's due/upcoming/acknowledged.

## MenuBar/
| File | Responsibility |
|---|---|
| `StatusItemController.swift` | Owns `NSStatusItem`, opens popover/menu, owns the 5s reminder-pulse `Timer` |
| `MenuBarClockView.swift` | Compact face; feeds `pulseColorScheme` into `SplitFlapClockFace.isDarkOverride` |
| `SecondClockStatusItemController.swift` / `SecondClockMenuBarView.swift` | Optional second timezone item |

## Popover/
| File | Responsibility |
|---|---|
| `PopoverClockView.swift` | Clock + `DateHeaderView` + `DueReminderBanner` (when something's due today) + `CalendarMonthView`, `showOwnGlassPanel: false` |
| `VibrantHostingController.swift` | Makes `NSVisualEffectView` the top-level content view to match `NSPopover` chrome |
| `CalendarMonthView.swift` | Month grid; double-click a day → `AddReminderView` popover; reminder dot mark per day; hover → inline overlay reminder preview card (see gotcha below — **not** a second `.popover`) |
| `DateHeaderView.swift` | Today's date header |

## DesktopOverlay/ (deep dive — the widget)

Floating, borderless `NSPanel` pinned near desktop-icon level, optional full-screen "fill screen" mode and DVD-bounce "float across screen" mode.

**Composition:**
```
OverlayWindow (NSPanel subclass)
  └─ NSHostingController(OverlayContentView)   [wired in OverlayWindowController]
       └─ OverlayContentView (SwiftUI root)
            ├─ SplitFlapClockFace (shared)         — HH:MM:SS(+AMPM)
            ├─ DateFlapRow (private)                — optional weekday+date flap row
            ├─ ReminderBadge overlay                — top-trailing corner, due/upcoming
            └─ .background(WidgetGlassBackground)   — frosted glass panel
```

| File | Responsibility |
|---|---|
| `OverlayWindow.swift` | `NSPanel` subclass: borderless, non-activating, transparent-backed, joins all Spaces, draggable by background. Native `hasShadow` is always off — see Known Gotchas |
| `OverlayWindowController.swift` | Creates window, wires SwiftUI content, reacts to settings changes, drives float-drift timer, masks the window's content view to the same rounded rect as the glass panel |
| `OverlayContentView.swift` | SwiftUI root: clock + optional date row + reminder badge, fixed padding, analytic `windowSize(...)` |
| `WidgetGlassBackground.swift` | Rounded-rect glass container. Renders the `DesktopBackdropCapture` blurred image when available, falls back to `NSVisualEffectView` (`.underWindowBackground`) otherwise; Reduce-Transparency fallback to opaque `.windowBackgroundColor` |
| `DesktopBackdropCapture.swift` | Captures the desktop behind the window (`CGWindowListCreateImage`, filtered to on-screen-below-window) and runs it through `CIGaussianBlur` on a background queue every 5s — this is what gives the widget stronger diffusion than a plain `NSVisualEffectView` can produce. Requires Screen Recording permission; falls back gracefully if denied |
| `SecondClockOverlayContentView.swift` / `SecondClockOverlayWindowController.swift` | Companion desktop widget for `settings.secondTimezoneID` — same glass treatment, sizing, and day/date/year row as the primary widget (all driven by the same settings), plus a small timezone-name label above the clock. Its own `OverlayWindow` + `DesktopBackdropCapture` instance; toggled by `settings.showSecondClockOverlay`. Deliberately skips float-across-screen/fill-screen — companion widget, not the main clock |

**Settings driving overlay appearance:** `showDesktopOverlay`, `overlaySize`, `showDateOnOverlay`, `timeFormat`, `meridiemStyle`, `theme`, `widgetColorStyle`, `floatAcrossScreen` (mutually exclusive with `fillScreen`), `fillScreen` (covers `NSScreen.main`, disables drag/shadow, corner radius→0, 1.6× extra scale). The second-clock widget additionally reads `secondTimezoneID` and is gated by `showSecondClockOverlay`.

**Current hardcoded visual constants:**
- **Corner radius:** `WidgetGlassBackground.cornerRadius(scale:)` = `(34 * scale).clamped(to: 14...40)`, forced to `0` in full-screen.
- **Padding:** `OverlayContentView.padding(scale:)` = `(16 * scale).clamped(to: 11...22)`.
- **Blur radius:** `DesktopBackdropCapture` blur radius = `(30 * overlaySize.scale).clamped(to: 16...50)`, computed in `OverlayWindowController.startBackdropCaptureIfNeeded()`.
- **Capture cadence:** 5s (was 1s — see `memory.md` for the resource-cost history).
- **Typography:** every character is rasterized into a bitmap card via `DigitFaceRenderer`, never live `Text`.

**Cross-module dependencies:** TimeEngine, Settings, Reminders, shared FlipClock/ rendering. No dependency on MenuBar/Popover in either direction.
