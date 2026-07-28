# CLAUDE.md

Project context for Claude Code when working in this repository.

## Documentation map

- `README.md` — user-facing features, setup, usage.
- `architecture.md` — full module-by-module map (supersedes the old `architecture-map.md`).
- `design.md` — visual design system: glassmorphism, typography, color tokens, reminder visual language.
- `phases.md` — chronological development milestones.
- `memory.md` — non-obvious lessons learned, narrated (the "why" behind gotchas below).
- `rules.md` — the fuller enforceable-rules checklist this file summarizes.

## Overview

FlipClock is a native macOS menu bar app (Swift + SwiftUI + AppKit) that renders an animated split-flap clock across three surfaces: a compact menu bar view, a popover with calendar, and a floating desktop overlay styled as a native widget (with an optional full-screen "liquid glass" mode). A shared `ReminderStore` adds lightweight reminders (add via double-click on a calendar day) surfaced across all three: a pulsing badge on the calendar/widget, a "Due Today" banner in the popover, and a subtle light/dark pulse on the menu bar clock until acknowledged. See `README.md` for user-facing features and setup.

The popover and desktop overlay default to a translucent "glass card" style (`glassCard: true` on `SplitFlapDigit`/`SplitFlapClockFace`) — digits render with no opaque card fill and sit on real vibrancy instead. The desktop widget's own background panel goes further: `DesktopBackdropCapture` captures and Gaussian-blurs the actual desktop behind the window (refreshed every 5s) for stronger, tunable diffusion than `NSVisualEffectView` alone can produce, falling back to live vibrancy if capture isn't available. The menu bar's compact rendering stays opaque (glass at 14×20pt in a status item isn't practical or legible). See the Known Gotchas below before touching anything glass-related — several of its behaviors are non-obvious `NSVisualEffectView`/CoreAnimation quirks, not stylistic choices.

## Tech Stack

- Swift 5.0, SwiftUI + AppKit, macOS 14.0+ deployment target
- No external dependencies
- Project generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`
- `FlipClockTests` (XCTest, unit target) covers the pure-logic and persistence layers — `ClockTick`, `DigitDelta`, `AppSettings`, `ReminderStore`, `CountdownTimer`, `Stopwatch` — including stress tests (rapid start/stop/reset cycling, hundreds of reminders) and a performance suite (`PerformanceTests.swift`, `measure` blocks over per-tick math, `DesktopBackdropCapture`'s capture-gating functions, and persistence throughput). Run via `xcodebuild test -project FlipClock.xcodeproj -scheme FlipClock -destination 'platform=macOS'`. `AppSettings`/`ReminderStore` both take an injectable `UserDefaults` (defaulting to `.standard`) specifically so tests never touch the real user's persisted preferences — always pass a throwaway `UserDefaults(suiteName:)` in new tests, never `.standard`. No UI/XCUITest coverage — the app's surfaces (menu bar, popover, desktop overlay) aren't practical to drive headlessly; SwiftUI view code is exercised manually per `README.md`'s testing guidance.

## Build & Verify

```bash
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

Always verify with a real build after edits — this codebase has repeatedly shown misleading stale SourceKit/index diagnostics in tool output that don't reflect actual build state. Trust `xcodebuild`'s `BUILD SUCCEEDED`/`FAILED`, not editor-reported diagnostics.

To run and visually check the desktop overlay:

```bash
open -n /path/to/DerivedData/.../Build/Products/Debug/FlipClock.app
```

The app is `LSUIElement` (no Dock icon, no visible window on launch) — check the menu bar and desktop overlay directly, e.g. via `screencapture`.

## Adding/Removing/Renaming Source Files

Regenerate the Xcode project rather than hand-editing `FlipClock.xcodeproj/project.pbxproj`:

```bash
xcodegen generate
```

Only hand-edit `project.pbxproj` if `xcodegen` isn't available — it requires adding matching `PBXBuildFile`, `PBXFileReference`, group-children, and `Sources` build-phase entries (all four, or the new file silently fails to compile with "cannot find type/symbol in scope").

## Known Gotchas

- **`NSWindow.frame` truncates to whole points.** Any per-tick animation that accumulates a sub-pixel offset (e.g. `OverlayWindowController`'s float-across-screen drift) must track its own precise `CGPoint` state and only ever *write* to `window.frame`/`setFrameOrigin`, never read the accumulator back from it — otherwise the fractional progress is silently discarded every frame and the window never visibly moves, despite the timer firing correctly.
- **The desktop overlay window intentionally sits below normal app windows** (level = desktop-icon level + 1), so any foreground app fully covers it — this is by design, matching how system widgets behave, not a bug.
- **Analytic size/layout math can drift from real SwiftUI layout** (e.g. worst-case weekday-width estimates vs. the actual rendered string). When a hosting window's frame is sized by hand-computed logic rather than measured, prefer making the content explicitly fill and center within that frame (`.frame(maxWidth: .infinity, maxHeight: .infinity)`) rather than relying on the window and content to agree exactly — otherwise undersized content gets pinned top-left instead of centered.
- Third-party windows (Notification Center widgets, other apps) have no queryable public API for frame/position — don't attempt to auto-align the overlay to them.
- **`NSVisualEffectView.behindWindow` blending stops re-sampling the desktop once fully covered** (e.g. by an opaque `CALayer` animating on top of it) and doesn't resume on its own — confirmed by pixel-sampling a screen recording: the same card position froze at one flat color for 200ms+ after a flip landed. Fix: toggle `.state = .inactive` then `.active` right when whatever was covering it goes away, which kicks the compositor back into live sampling (see `CardGlassBackground`/`VisualEffectCardBlur` in `SplitFlapDigit.swift`).
- **A CALayer property assigned in a transaction that doesn't call `CATransaction.setDisableActions(true)`** also picks up CoreAnimation's own implicit action for that keypath, which runs *alongside* any explicit `CABasicAnimation` you add right after — two competing animations on the same property, at different durations/curves, composite into a visible glitch (looked like the flip-clock digit "double-exposing" mid-rotation). Always disable implicit actions in any transaction where you're driving the same property with an explicit animation.
- **The animating flap in a "glass" card must stay opaque (or translucent-but-still-covering), never fully transparent**, even though the idle resting card is meant to be see-through — the flap sits on top of the stale static digit during rotation, and if it's transparent that old digit bleeds through and reads as a ghost/double-exposure. Only the resting card should be see-through; the flap gets its own translucent fill (`FlapColors.glassFlapFill`) tuned to look close to the resting tone without depending on a live blur sample (a static rasterized `CALayer` face can't sample one).
- **Popovers are not desktop-level windows.** Giving a card its own `NSVisualEffectView.behindWindow` panel (as the desktop overlay does, to sample the real wallpaper) just grays things out flatly in a popover, because there's no meaningful desktop content directly behind a popover window. Popover content should instead render fully transparent (`transparentBackground: true`, no per-card blur panel — see `showOwnGlassPanel` on `SplitFlapDigit`/`SplitFlapClockFace`) and ride on the popover's own existing vibrancy (`VibrantHostingController`).
- **`NSVisualEffectView`'s blur radius is fixed by its material and isn't a public API.** No amount of `.opacity()` tuning can push diffusion strength past it — this is why the desktop widget's glass kept reading "weaker" than native Notification Center widgets no matter how the opacity was tuned. `DesktopBackdropCapture` (capture + `CIGaussianBlur` with a radius we control) is the fix; don't try to solve blur-strength complaints by tuning `NSVisualEffectView` opacity again.
- **`.preferredColorScheme()` doesn't reliably re-propagate to `@Environment(\.colorScheme)` reads on *updates* when hosted inside an `NSStatusItem` button.** Confirmed the hard way building the reminder pulse: the state genuinely changed every 5s (verified via `NSLog`), but nothing repainted. Fix: pass an explicit override parameter (`SplitFlapClockFace.isDarkOverride`) instead of relying on the environment, and force `statusItem.button?.needsDisplay = true` alongside any `NSHostingView.rootView` reassignment.
- **A `.popover()` triggered from inside content already itself presented via `NSPopover` doesn't reliably present.** `CalendarMonthView`'s hover-preview card had to become a plain inline `.overlay()` instead of a nested popover for exactly this reason.
- **`strings <binary>` cannot verify Swift code actually compiled**, and plain `print()` from a GUI app launched via `open` doesn't reach a capturable stream — use `NSLog()` + `log show --predicate 'process == "FlipClock"'` for debug output instead. Note `log` is also a zsh shell builtin unrelated to the macOS `log` CLI — call `/usr/bin/log` explicitly or it silently fails with "too many arguments".
- **`.animation(_:value:)` and `matchedGeometryEffect` both animate a view's entire layout-derived position, not just the property you intended** — confirmed the hard way building `SettingsView`'s sliding tab-selection pill: whichever of the two was attached, a transient re-layout during a large tab-to-tab content-height change (e.g. General → Appearance, the biggest height delta of any tab pair) got eased into a visible diagonal arc, while small-delta pairs looked like a clean slide — an asymmetry that survived several rounds of fixes aimed at the window-resize/`matchedGeometryEffect` coupling because the real cause was simpler: any animatable change in the modifier's subtree eases, including ones from layout, not just the one state change you meant to animate. Fixed by driving the pill from a plain `@State` scalar offset assigned inside `withAnimation` at the call site, with no `.animation` modifier anywhere near the pill — isolates the animation to that one number. Diagnosing this required tracking the pill's full bounding box (x, y, width, *and* height) frame-by-frame in a real screen recording; tracking x alone looked perfectly clean and completely hid the vertical bounce.
- **An animated `NSWindow` frame around a hosted SwiftUI view transiently misplaces top-aligned content while the window grows.** `NSHostingView` lays out in AppKit's bottom-left origin space, so while `animator().setFrame` grows a window with its top edge pinned, it's the *bottom* edge that's actually moving — top-aligned SwiftUI content can render low and creep back up as layout catches up to each intermediate frame. Pinning the hosting view to the window's top via a container + `.minYMargin` autoresizing does **not** fix this — `NSHostingView` installs its own Auto Layout constraints and ignores `autoresizingMask` entirely (made the misplacement worse in testing). The settings window's resize is unanimated (`animate: false`) specifically to sidestep this rather than fight it.
- **A repeating `Timer` tied to one setting (e.g. `floatAcrossScreen`) but not to whether its window is even visible (`showDesktopOverlay`) keeps firing forever once enabled**, doing real work (window moves, screen captures) nobody can see and defeating App Nap. Found twice in this codebase — `DesktopBackdropCapture`'s 5s capture-and-blur cycle and `OverlayWindowController`'s 30Hz float-drift timer — both fixed by having the visibility-owning code path (`setVisible`) explicitly stop/restart the dependent timer, not just relying on the one setting that toggles it on. When adding a new per-window timer, gate it on actual window visibility, not just the feature flag that conceptually "turns it on."
- **SwiftUI view structs rebuilt every tick (driven by a live `Publisher` like `TimeProvider.tick`) must not allocate inside computed properties read from `body`.** `DateFlapRow` allocated a fresh `DateFormatter` (and rebuilt a `Calendar`) on every one-second re-render for values that only change once a day — `DateFormatter` construction resolves locale/calendar/timezone and isn't cheap. Cache by whatever varies (format string here) as a `static`/instance-cached dictionary instead of reconstructing per access; `DateHeaderView` already did this correctly with `static let` formatters, which is what exposed the inconsistency.

## Conventions

- No comments except where a non-obvious constraint/workaround/invariant needs explaining (see existing doc comments in `DesktopOverlay/` for the expected style/density).
- Match existing SwiftUI/AppKit split: AppKit for window level, collection behavior, login items, status items; SwiftUI for content views and settings UI.
- `AppSettings` is the single source of truth for persisted preferences (`UserDefaults` + Combine `@Published`); don't introduce a second settings store.
