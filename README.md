# FlipClock

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.0-orange)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-93%20passing-brightgreen)](#running-tests)
[![License](https://img.shields.io/badge/license-unspecified-lightgrey)](#license)

A native macOS split-flap clock. Lives in the menu bar, expands into a popover with a calendar, timer and stopwatch, and puts a floating desktop widget on your wallpaper that is built to be visually indistinguishable from Apple's own.

Every character on every surface — digits, weekday, date, AM/PM — is a real rasterized flip card with a two-housing flip animation, not styled text.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Permissions](#permissions)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Testing](#testing)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Features

**Clock surfaces**

- Menu bar clock with live split-flap animation
- Popover with three tabs — Calendar, Timer, Stopwatch
- Native Liquid Glass controls on macOS 26+, clearer calendar/timer/stopwatch color cues, and gentle spring transitions; adaptive controls on older macOS, with Reduce Motion and Reduce Transparency support
- Desktop widget styled to match native macOS widgets, positionable anywhere, with optional drift-across-screen and a full-screen mode
- Up to 5 world clocks in other time zones, each as a named menu bar item ("TOKYO 07:22 PM"), its own desktop widget, or both — with its own widget size and 12/24-hour format

**Desktop widget glass**

The widget doesn't rely on `NSVisualEffectView` alone — its blur radius is fixed by the system material and can't reach what Apple's widgets show. Instead it captures the wallpaper (only the wallpaper — never app windows in front of it) via ScreenCaptureKit and applies its own tunable Gaussian blur, then matches native widget glass on three measured axes: diffusion, tone, and a saturation boost. It also follows macOS's own **Dim widgets on desktop** setting: under Automatic it fades to its dimmed look while an app is in front and back to full colour when you click the wallpaper, in step with the widgets beside it.

Falls back gracefully: live vibrancy before the first capture lands or if Screen Recording is denied, and an opaque fill when Reduce Transparency is on.

**Reminders**

Select a calendar date and choose Add Reminder, or double-click the date, to add a reminder with a precise time. The day gets a pulsing badge (orange = within 24h, red = due today), the popover shows a "Due Today" banner, and the menu bar clock subtly pulses in opacity every 5 seconds until acknowledged, keeping the selected theme.

Timed reminders use native macOS notifications, including while FlipClock is closed. In Settings › General › Reminders, enable notifications and choose Default or a built-in macOS alert sound; the speaker button previews the selected sound. Changing the sound updates pending reminders; acknowledging or removing a reminder cancels its pending alert. Newly added overdue reminders alert immediately; historical overdue reminders aren't replayed on launch.

Choose Dismiss on a notification, or close it, to acknowledge the reminder and remove its active banner/widget entry. Acknowledgment persists across relaunches; the completed reminder stays in calendar history. macOS owns notification sound playback: sounds play once, and there is no public API to interrupt them mid-playback.

The desktop clock shows reminder details below the date as “Today @ time – reminder”, with up to two rows and a count of additional reminders in the calendar.

**Customisation**

37 bundled decorative digit fonts, light/dark/system theme, 12/24-hour time, four widget sizes, AM/PM as text or a sun/moon icon, Full Color / Monochrome widget style, and launch-at-login.

## Requirements

| | |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 16 or later |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Only to regenerate `.xcodeproj` from `project.yml` |

## Getting Started

```bash
git clone https://github.com/1mrajeevranjan/FlipClock.git
cd FlipClock
open FlipClock.xcodeproj
```

Build and run the `FlipClock` scheme (⌘R).

Or run `./script/build_and_run.sh` (also available from Codex's Run action). Use `--verify` to check launch or `--debug` to open LLDB.

### Code signing

`project.yml` pins a specific `DEVELOPMENT_TEAM`. Change it to your own before building:

```yaml
CODE_SIGN_STYLE: Manual
CODE_SIGN_IDENTITY: "Apple Development"
DEVELOPMENT_TEAM: YOUR_TEAM_ID   # `security find-identity -v -p codesigning`
```

Then `xcodegen generate`.

Use a real signing identity rather than ad-hoc signing. Ad-hoc (`--sign -`) puts the binary's own hash into the app's designated requirement, so **every rebuild looks like a new app to macOS and the Screen Recording grant is discarded** — meaning a permission prompt on every single build. The test bundle needs matching signing too; it's loaded into the host app, and macOS refuses to map a bundle whose Team ID differs from the loading process.

### Command-line build

```bash
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Debug build
```

### Regenerating the Xcode project

Sources are defined in `project.yml`; the generated `FlipClock.xcodeproj` is committed. After adding, removing, or renaming files, regenerate rather than hand-editing `project.pbxproj`:

```bash
xcodegen generate
```

## Permissions

**Notifications** — enable in Settings › General › Reminders, or allow the macOS prompt when adding your first reminder. If previously denied, allow FlipClock in System Settings › Notifications. Alerts and sounds follow the system's notification and Focus settings.

**Screen Recording** — required only for the desktop widget's glass, which samples the wallpaper behind the window to blur it. macOS prompts on first capture. If you decline, everything still works; the widget just falls back to softer system vibrancy.

No data leaves your machine. The captured frame is blurred in memory, drawn into the widget, and never written to disk or transmitted.

## Usage

FlipClock is an `LSUIElement` agent — no Dock icon, no app window.

The app icon is generated from the root `icon.png` at every macOS icon size, shared by Finder, About, and native notifications.

| Action | Result |
|---|---|
| Left-click menu bar clock | Opens the popover (Calendar / Timer / Stopwatch) |
| Right-click menu bar clock | Settings, More (About, Support, Tips, FAQ, Website, Rate, Share), Quit |
| Click a calendar date, then Add Reminder (⌘N) | Add a reminder for that day; double-click also works |
| Click the calendar month/year heading | Show months; click the year heading again to browse years |
| Click calendar arrows (⌘← / ⌘→) | Move by month, year, or a page of 12 years |
| Drag the desktop widget | Reposition it |

### Settings

Settings uses a resizable window with sidebar navigation, scrollable pages, and a clock preview. World-clock changes apply after choosing a time zone; Cancel leaves the current clocks unchanged.

| Tab | Controls |
|---|---|
| General | Show desktop clock, launch at login, reminder notification access and sound |
| Appearance | Theme, AM/PM style, digit font |
| Desktop Clock | Size, time format, colour style, date row, float across screen, fill screen |
| World Clocks | Up to 5 clocks: time zone, optional name, show in (off / menu bar / widget / both), widget size, 12/24-hour |

## Project Structure

```text
FlipClock/
  App/              Entry point and AppKit bridge (AppDelegate, FlipClockApp)
  CountdownTimer/   Timer, stopwatch, wheel picker, flip time display
  DesktopOverlay/   Overlay window, glass background, ScreenCaptureKit backdrop capture
  FlipClock/        Split-flap rendering (clock face, digits, flap layer, fonts)
  MenuBar/          Menu bar clock views and status item controllers
  Popover/          Popover, calendar, vibrant hosting controller
  Reminders/        Model, store, add form, badge, due-today banner
  Settings/         AppSettings, settings window and SwiftUI view
  TimeEngine/       Tick generation and time/digit maths
FlipClockTests/     Unit, stress, and performance tests
```

## Architecture

- **`TimeProvider`** publishes clock ticks consumed across every surface.
- **`SplitFlapClockFace`** renders the animated face; menu bar, popover, and widget all share this one implementation at different scales.
- **`DigitFaceRenderer`** rasterizes each glyph to a bitmap card — this is what makes the physical flip animation possible, and it's the app's core identity rather than an implementation detail to simplify away.
- **`OverlayWindowController`** owns the widget `NSPanel`: window level, size, position, and drift animation.
- **`WidgetGlassBackground` + `DesktopBackdropCapture`** produce the widget's glass.
- **`StatusItemController`** owns the menu bar clock, popover, context menu, and reminder pulse.
- **`AppSettings`** persists preferences to `UserDefaults` and publishes via Combine. **`ReminderStore`** does the same for reminders (JSON), shared by reference across surfaces.

Both stores take an injectable `UserDefaults` so tests never touch real preferences.

## Resource use

- The stopwatch keeps its 30ms display cadence only in the visible Stopwatch tab. Hidden stopwatches keep elapsed time without a repeating timer and catch up immediately on reopening.
- Hidden countdowns use one completion alarm rather than a timer every second. Popover clock observation and reminder pulses stop when closed; calendar layout is separate from clock ticks.
- Covered desktop widgets freeze their time updates and pause automatic drift. Date cards redraw when their local date or appearance changes.
- Glyph bitmaps use a shared `NSCache` with a 64 MiB cost target and 2,048-entry limit, allowing macOS to reclaim cached images. This is a cache target, not a limit on total app memory.
- Concurrent matching wallpaper requests share one capture/blur task. Duplicate drag crops are skipped, and hidden widgets release their private backdrop references. Existing 60s/180s wallpaper refresh intervals remain.
- Bulk reminder acknowledgment publishes and persists once; repeated acknowledgments and removals of missing reminders do no work.

Development spot check (2026-10-18, Debug build, popover closed): eleven one-second CPU samples averaged 1.08% before and 0.39% after. Reported memory was 113 MB in the older session and 72 MB after relaunch; session lifetimes differ, so this is not a sustained-memory comparison. GPU energy and battery runtime were not measured.

## Testing

```bash
xcodebuild test -project FlipClock.xcodeproj -scheme FlipClock -destination 'platform=macOS'
```

110 tests covering time and digit maths, settings persistence and fallbacks, calendar navigation, popover appearance updates, rendered timer-lens visibility and magnification in both themes and between values, reminder notification requests, sounds and dismissal, timer and stopwatch — including hidden-tool accuracy, popover reopening, concurrent capture deduplication, image-cache reuse, local-date rendering, batched reminder updates, stress tests and performance measurements.

`InteractionStressTests` adds 1,000 mixed tool/control cycles, 9,600 calendar month-page moves, 300 settings/world-clock cycles, 500 reminder records, 1,000 component key events, menu-handler checks, and bundled-font/icon validation. Repeat the suite in fresh processes with `-test-iterations 3 -test-repetition-relaunch-enabled YES -parallel-testing-enabled NO`.

XCTest covers models, offscreen components, rendering and menu wiring. Live click-through, native permission dialogs, audible playback, and desktop gestures still require manual verification. See [QA.md](QA.md) for results and remaining checks.

## Documentation

| File | Contents |
|---|---|
| [`architecture.md`](architecture.md) | Full module-by-module map |
| [`design.md`](design.md) | Visual design system, glass tuning, measurement method |
| [`memory.md`](memory.md) | Non-obvious lessons and platform gotchas |
| [`phases.md`](phases.md) | Development milestones |
| [`rules.md`](rules.md) | Enforceable project rules |
| [`CLAUDE.md`](CLAUDE.md) | Context for AI coding assistants |

`design.md` and `memory.md` are worth reading before touching anything glass- or animation-related — several behaviours that look like stylistic choices are actually workarounds for specific AppKit and Core Image quirks, each documented with the symptom that motivated it.

## Contributing

Issues and pull requests welcome.

Before submitting:

1. `xcodebuild ... build` passes.
2. `xcodebuild test ...` passes.
3. New files added via `project.yml` + `xcodegen generate`, not by hand-editing `project.pbxproj`.
4. Comments explain *why*, not *what* — match the density of the existing doc comments in `DesktopOverlay/`.

## License

No license has been specified. All rights reserved by the author unless stated otherwise.

If you intend this to be open source, add a `LICENSE` file — without one, others have no legal right to use, modify, or distribute the code, regardless of it being publicly visible.
