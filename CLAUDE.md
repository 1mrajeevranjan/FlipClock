# CLAUDE.md

Project context for Claude Code when working in this repository.

## Overview

FlipClock is a native macOS menu bar app (Swift + SwiftUI + AppKit) that renders an animated split-flap clock across three surfaces: a menu bar view, a popover with calendar, and a floating desktop overlay styled as a native widget. See `README.md` for user-facing features and setup.

## Tech Stack

- Swift 5.0, SwiftUI + AppKit, macOS 14.0+ deployment target
- No external dependencies
- Project generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`
- No test target currently exists

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

## Conventions

- No comments except where a non-obvious constraint/workaround/invariant needs explaining (see existing doc comments in `DesktopOverlay/` for the expected style/density).
- Match existing SwiftUI/AppKit split: AppKit for window level, collection behavior, login items, status items; SwiftUI for content views and settings UI.
- `AppSettings` is the single source of truth for persisted preferences (`UserDefaults` + Combine `@Published`); don't introduce a second settings store.
