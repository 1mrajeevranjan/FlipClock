# FlipClock Development Rules

Enforceable conventions for this repo. `CLAUDE.md` is the entry-point summary for AI agents; this file is the fuller checklist. `memory.md` and `design.md` explain the *why* behind several of these.

## Build & verify

1. Always verify changes with a real build: `xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build`. Trust `BUILD SUCCEEDED`/`FAILED` only — this codebase has repeatedly shown stale SourceKit/editor diagnostics that don't reflect real build state.
2. After adding, removing, or renaming any source file, run `xcodegen generate` before building. Hand-editing `project.pbxproj` requires four matching entries (`PBXBuildFile`, `PBXFileReference`, group-children, `Sources` build-phase) — miss one and the file silently fails to compile with a misleading "cannot find type/symbol" error.
3. Prefer visual confirmation over claims. Screenshot the actual running app (menu bar, popover, desktop widget) after UI changes — don't declare a visual fix "done" from code review alone, and don't trust a single screenshot if the state could be stale (relaunch the app after every rebuild that touches rendering code).
4. `strings <binary>` is not a valid way to confirm Swift code compiled — don't use it as a verification step (see `memory.md`).
5. Prefer `NSLog()` over `print()` when you need debug output captured from a GUI app launched via `open`/Finder — plain `print()` doesn't reach a capturable stream in that launch path. Remove all debug logging before committing.

## Architecture

6. `AppSettings` is the single source of truth for persisted preferences (`UserDefaults` + Combine `@Published`). Don't introduce a second settings store.
7. `ReminderStore` is the single source of truth for reminder data, shared by reference from `AppDelegate` across all three surfaces. Don't create a second instance.
8. `TimeProvider` is created once and injected everywhere — never instantiate a second one, or surfaces will drift relative to each other and burn extra CPU on duplicate timers.
9. Match the existing AppKit/SwiftUI split: AppKit for window level, collection behavior, login items, status items; SwiftUI for content views and settings UI.
10. `SplitFlapClockFace` is the one shared rendering engine for menu bar, popover, and desktop overlay. Don't fork a second implementation for a new surface — extend the shared one with a new parameter instead (see `isDarkOverride` as the precedent).

## SwiftUI/AppKit interop caution

11. Don't rely on `.preferredColorScheme()` to propagate to descendant `@Environment(\.colorScheme)` reads on *updates* when the view is hosted inside an `NSStatusItem` button — it doesn't reliably. Use an explicit view parameter instead for anything that needs to change after initial render in that context.
12. Don't nest a `.popover()` inside content that's already itself presented via `NSPopover` — it silently fails to present. Use an inline `.overlay()` for secondary contextual UI within an already-popover-hosted view.
13. When forcing a repaint on an `NSStatusItem`'s custom view content, mark `statusItem.button?.needsDisplay = true` explicitly — its button composites through a separate pipeline that doesn't auto-invalidate the way a normal window's content view does.
14. Any per-tick animation that accumulates a sub-pixel offset must track its own precise `CGPoint`/state and only ever *write* to `NSWindow.frame` — `NSWindow.frame` truncates to whole points, so reading the accumulator back from it silently discards fractional progress every frame.
15. Disable implicit CALayer actions (`CATransaction.setDisableActions(true)`) in any transaction where you're also driving that property with an explicit `CABasicAnimation` — otherwise both animations run simultaneously and composite into a visible glitch.

## Code style

16. No comments except where a non-obvious constraint, workaround, or invariant needs explaining. Don't describe *what* code does (names should do that); explain *why* when the reason isn't obvious from reading it.
17. Don't add features, abstractions, or defensive handling beyond what's asked. No speculative generality, no unused parameters "for future flexibility."
18. Match existing code style and patterns in the file/module being edited over introducing a new pattern, even if you'd personally prefer the new one.
19. Files should stay focused — this codebase already favors many small, single-responsibility files (e.g. `Reminders/` splits model, store, badge, banner, and form into five separate files) over fewer large ones. Follow that pattern for new modules.

## Product/scope discipline

20. The split-flap flip animation and bitmap-rasterized-character rendering are the product's core identity — don't "simplify" toward live `Text` rendering or a simpler crossfade without an explicit decision to do so.
21. The tint/accent-color feature was built and then fully removed at explicit user request. Don't reintroduce a persistent accent-color setting without a new explicit ask — if tint-related code resurfaces in a diff, treat it as something to remove, not extend.
22. Menu bar compact rendering stays opaque, never glass — this is a legibility/practicality decision at 14×20pt, not an oversight to "fix."
23. Popovers never get their own per-card `behindWindow` blur panel — there's no meaningful desktop content behind a popover for that blend mode to sample. They ride on the popover's own vibrancy instead.

## Accessibility

24. Respect Reduce Transparency: any translucent/glass surface needs an opaque fallback (see `WidgetGlassBackground` and `VibrantHostingController` for the pattern — OS accommodation overrides any per-app preference, doesn't blend with it).
25. Reduce Motion is not yet handled for the flip animation or float-across-screen drift — this is a known, deliberate gap (flagged in `phases.md`), not something to silently patch with a guess. Raise it as a decision before changing animation behavior for accessibility.

## Git / commits

26. Only commit when explicitly asked. Keep commit messages focused on *why*, not a restated diff.
27. Regenerate `FlipClock.xcodeproj` via `xcodegen generate` and include the resulting `project.pbxproj` diff in the same commit as any source-file addition/removal/rename.
