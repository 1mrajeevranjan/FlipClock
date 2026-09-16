# FlipClock

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.0-orange)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-61%20passing-brightgreen)](#running-tests)
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
- Desktop widget styled to match native macOS widgets, positionable anywhere, with optional drift-across-screen and a full-screen mode
- Optional second clock in another time zone, as a menu bar item, a second desktop widget, or both

**Desktop widget glass**

The widget doesn't rely on `NSVisualEffectView` alone — its blur radius is fixed by the system material and can't reach what Apple's widgets show. Instead it captures the desktop behind the window via ScreenCaptureKit and applies its own tunable Gaussian blur, then matches native widget glass on three measured axes: diffusion, tone, and a saturation boost. It also follows macOS's own **Dim widgets on desktop** setting, so it flattens and brightens in step with the widgets beside it.

Falls back gracefully: live vibrancy before the first capture lands or if Screen Recording is denied, and an opaque fill when Reduce Transparency is on.

**Reminders**

Double-click any calendar date to add a reminder with a precise time. The day gets a pulsing badge (orange = within 24h, red = due today), the popover shows a "Due Today" banner, and the menu bar clock pulses light/dark every 5 seconds until acknowledged.

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

**Screen Recording** — required only for the desktop widget's glass, which samples the wallpaper behind the window to blur it. macOS prompts on first capture. If you decline, everything still works; the widget just falls back to softer system vibrancy.

No data leaves your machine. The captured frame is blurred in memory, drawn into the widget, and never written to disk or transmitted.

## Usage

FlipClock is an `LSUIElement` agent — no Dock icon, no app window.

| Action | Result |
|---|---|
| Left-click menu bar clock | Opens the popover (Calendar / Timer / Stopwatch) |
| Right-click menu bar clock | Settings, More (About, Support, Tips, FAQ, Website, Rate, Share), Quit |
| Double-click a calendar date | Add a reminder |
| Drag the desktop widget | Reposition it |

### Settings

| Tab | Controls |
|---|---|
| General | Show desktop clock, launch at login |
| Appearance | Theme, AM/PM style, digit font |
| Desktop Clock | Size, time format, colour style, date row, float across screen, fill screen |
| Second Clock | Display (off / menu bar / widget / both), time zone |

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

## Testing

```bash
xcodebuild test -project FlipClock.xcodeproj -scheme FlipClock -destination 'platform=macOS'
```

61 tests covering time and digit maths, settings persistence and fallbacks, reminders, timer and stopwatch — including stress tests (rapid start/stop/reset cycling, hundreds of reminders) and a performance suite over per-tick maths, capture gating, and persistence throughput.

There is no UI test coverage: the menu bar, popover, and desktop overlay aren't practical to drive headlessly, so SwiftUI view code is verified manually.

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
