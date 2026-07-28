# FlipClock Development Phases

Chronological log of major milestones, newest first. See `git log` for the exact commit-level history — this is the "why phases happened" summary, not a changelog duplicate.

## Phase 10 — Performance/battery pass (current)

- Added `PerformanceTests.swift` (6 tests, `measure` blocks + correctness checks) covering `ClockTick.at`/`DigitDelta.diff` per-tick math, `DesktopBackdropCapture`'s pure gating functions, and `ReminderStore`/`AppSettings` persistence throughput under load.
- `DesktopBackdropCapture` ran its screen-capture + Gaussian-blur cycle (the single most expensive operation in the app) unconditionally every 5s forever, including while the overlay window sat fully covered by another app — the documented common case, since the overlay is deliberately layered below normal windows. Fixed by gating on `NSWindow.OcclusionState.contains(.visible)` (`shouldCapture(occlusionState:)`, pulled out pure/testable), with an occlusion-change observer for immediate refresh on becoming visible again instead of waiting out the interval. Also stretches the refresh interval from 5s to 15s under Low Power Mode.
- `OverlayWindowController`'s float-across-screen drift timer (30Hz) was gated only on `settings.floatAcrossScreen`, independent of `settings.showDesktopOverlay` — enabling float and then hiding the widget left the timer stepping a window nobody could see, forever. Fixed by having `setVisible` stop/restart the float timer alongside the backdrop capture.
- `OverlayContentView`'s `DateFlapRow` allocated 4 fresh `DateFormatter`s (plus a `Calendar` copy) on every render — and it re-renders every second, driven by the live clock tick — for values (weekday/date/year) that only actually change once a day. Fixed by caching formatters per format string (matching the pattern `DateHeaderView` already used) and hoisting the base `Calendar`.
- Found via a dedicated subagent sweep of every `Timer`/`NotificationCenter` usage in the codebase specifically looking for the two bug classes above (unconditional timers, per-render allocation) — `Stopwatch`, `CountdownTimer`, `TimeProvider`, and `StatusItemController`'s reminder pulse timer were all checked and found correctly gated/invalidated already.

## Phase 9 — Test infrastructure

- Added `FlipClockTests`, the project's first test target — 51 XCTest cases covering `ClockTick`/`DigitDelta` (pure time/digit math), `AppSettings` and `ReminderStore` (persistence round-trips, edge cases, corrupted-data fallbacks), and `CountdownTimer`/`Stopwatch` (real-timer behavior plus rapid start/stop/reset stress cycling).
- `AppSettings` and `ReminderStore` both switched from hardcoded `UserDefaults.standard` to an injectable `UserDefaults` parameter (defaulting to `.standard`) — required so tests can use an isolated suite instead of risking the real user's persisted preferences.
- A handful of initial test failures were the tests' own bugs, not app bugs: `CountdownTimer.inputMinutes` defaults to 5, so setting only `inputSeconds` in a couple of tests silently produced a 303-second countdown instead of 3; a midnight-rollover digit-delta test asserted "every position changes," but the hour-tens digit genuinely doesn't (11 -> 12 keeps the same tens digit in 12-hour format) — both fixed by correcting the test, not the app.

## Phase 8 — Settings window polish

- Sliding tab-selection pill in `SettingsView`'s custom header, replacing four independently-fading per-button backgrounds.
- Long debugging arc chasing an animation asymmetry (pill "bounces" on General↔Appearance, slides cleanly on other pairs) through several plausible-but-wrong fixes — `matchedGeometryEffect`, `.overlay()` → `ZStack` restructuring, an animated `NSWindow` resize with pinned hosting view — before the real cause (`.animation(_:value:)`/`matchedGeometryEffect` animating a view's entire layout-derived position, not just the intended property) was isolated by tracking the pill's full bounding box at 60fps instead of just its x-position. Fixed with an explicit `@State` scalar offset animated via `withAnimation`. Full trail in `memory.md`.
- Settings window resize switched to unanimated — an animated `NSWindow` frame independently misplaces top-aligned `NSHostingView` content mid-grow.
- Replaced `GroupBox`-based settings cards with a plain custom `VStack`+background (GroupBox's hidden internal padding survives even a custom `GroupBoxStyle`).
- Hairline `Divider` added between the tab row and card content; header/content split into `ZStack` siblings instead of `.overlay()`.

## Phase 7 — Reminders

- `Reminders/` module: `Reminder` model, `ReminderStore` (UserDefaults-JSON), shared across popover/widget/menu bar.
- Add via double-click on a calendar day; precise "@ time" picker (not just the moment double-clicked).
- Visual language: pulsing dot badge (red = due today, orange = upcoming within 24h) on calendar day cells and the desktop widget's corner.
- "Due Today" banner in the popover with a per-reminder acknowledge checkmark.
- Menu bar clock pulses light/dark every 5s while something's due and unacknowledged, until acknowledged via the banner.
- Hover-to-preview on calendar days: implemented as an inline `.overlay`, not a nested `.popover` — see `memory.md`, a `.popover` triggered from inside content already hosted in a popover doesn't reliably present.

## Phase 6 — Resource optimization

- Desktop widget's screen-capture + Gaussian-blur cadence cut from 1s to 5s — was the single largest CPU/battery cost for content (desktop wallpaper/icons) that rarely changes frame to frame.

## Phase 5 — Real desktop-capture blur + corner/style polish

- Replaced live `NSVisualEffectView` blur with a captured-and-blurred still image (`DesktopBackdropCapture`): `CGWindowListCreateImage` + `CIGaussianBlur`, refreshed on a timer. `NSVisualEffectView`'s blur radius is fixed by its material and isn't a public API — no amount of opacity tuning could push diffusion strength further, so this became the only way to close the gap with Notification Center's own widget strength.
- Fixed a real corner-clipping bug: the captured image rendered at full bitmap resolution instead of the widget's actual size (`GeometryReader`-forced frame fixed it).
- Fixed the native-window-shadow square-edge-bleed-past-rounded-corners bug (turned off `NSWindow.hasShadow` entirely; `WidgetGlassBackground` draws its own correctly-shaped shadow).
- Added a glossy specular rim (`AngularGradient` stroke) and a Full Color / Monochrome widget style toggle.
- One dead end kept for the record: stacking a SwiftUI `.ultraThinMaterial` on top of the live blur to boost diffusion — washed the whole panel to near-opaque white and had to be reverted.

## Phase 4 — Fonts

- 30 bundled decorative fonts (`Fonts/`), then +14 more (37 total), then −7 removed after the user reported they lack usable digit glyphs.
- Real sun.png/moon.png images for the AM/PM meridiem icon, replacing the emoji glyphs (font-independent, no risk of a decorative font mangling ☀️/🌙).
- `WidgetFont` catalog resolves real PostScript names via CoreText (not filename guesses) and registers each font with `CTFontManagerRegisterFontsForURL` at launch.

## Phase 3 — Desktop widget HIG pass

- Corner radius, padding, and shadow scaled to `overlaySize` instead of flat constants, matching Apple's Widget HIG guidance that widget chrome should track container size.
- Full-screen "liquid glass" mode.
- Fixed the flip-animation/glass-consistency bugs cataloged in `CLAUDE.md`'s Known Gotchas (double-exposure on flip, `NSVisualEffectView` freezing after being covered, implicit-vs-explicit CALayer animation conflicts).

## Phase 2 — Tint (added, then fully removed)

- Added an HIG-style accent-tint customization feature, then removed it completely per explicit user request in favor of the font-customization direction instead. `widgetTintColor`/`widgetTintEnabled` UserDefaults keys are stale leftovers from this — harmless, unread by current code.

## Phase 1 — Core split-flap engine

- Shared `SplitFlapClockFace` rendering engine used identically (at different scales) by the menu bar, popover, and desktop overlay.
- `TimeProvider`/`ClockTick`/`DigitDelta` time engine.
- Desktop overlay window mechanics: positioning, drag, float-across-screen drift, the `NSWindow.frame`-truncation sub-pixel-drift bug and its fix.

## Open / not yet done

- No UI/XCUITest coverage — only `FlipClockTests` (unit/integration/stress, logic + persistence layers). See `CLAUDE.md`.
- Screen Recording permission re-prompts on every dev rebuild (ad-hoc signing identity changes per build) — expected in local dev, won't happen in a real signed release, but worth knowing before assuming a permission bug.
- Hover-preview card on the calendar hasn't been visually confirmed working end-to-end with a real (non-synthetic) mouse hover — the inline-overlay fix is a strong theoretical fix for the popover-in-popover failure mode, but live verification was interrupted (see `memory.md`).
