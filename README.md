# FlipClock

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-unspecified-lightgrey)](#license)

A native macOS split-flap clock: menu bar clock, popover view with calendar, a floating desktop overlay styled like a native widget, and a configurable settings window.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Development Notes](#development-notes)
- [Contributing](#contributing)
- [License](#license)

## Features

- Menu bar clock with live split-flap animation
- Full popover clock with calendar, date header, and reminders
- Desktop overlay clock styled like a native macOS widget — real captured-and-blurred desktop glass (not just system vibrancy), positionable anywhere on screen or set to drift/bounce across it, with an optional full-screen "liquid glass" mode
- Full Color / Monochrome widget style, matching macOS's own desktop-widget color option
- 37 bundled decorative digit fonts, plus a real image-based sun/moon AM/PM icon
- **Reminders:** double-click any calendar date to add one (with a precise "@ time"); a pulsing badge marks the day and the widget; a "Due Today" banner appears in the popover; the menu bar clock pulses light/dark every 5s until you acknowledge it
- Optional second menu bar clock in a different time zone
- Configurable appearance, time format, overlay size, and AM/PM style
- Launch-at-login support
- Settings window that resizes per tab instead of leaving blank space

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (only needed if regenerating the `.xcodeproj` from `project.yml`)

## Getting Started

Clone the repo and open the project in Xcode:

```bash
git clone https://github.com/1mrajeevranjan/FlipClock.git
cd FlipClock
open FlipClock.xcodeproj
```

Build and run the `FlipClock` scheme (⌘R).

### Command-line build

```bash
xcodebuild -project FlipClock.xcodeproj \
  -scheme FlipClock \
  -configuration Debug \
  build
```

### Regenerating the Xcode project

The project is defined in `project.yml` and the generated `FlipClock.xcodeproj` is checked into the repo. After adding, removing, or renaming source files, regenerate the project rather than hand-editing `project.pbxproj`:

```bash
xcodegen generate
```

## Usage

FlipClock is a menu bar app (`LSUIElement`) — it has no Dock icon. Click the menu bar clock to open the popover, or open Settings from there to configure:

| Tab | Controls |
|---|---|
| General | Launch at login, second clock |
| Appearance | Theme, popover glassiness, AM/PM style, digit font |
| Desktop Clock | Show/hide overlay, size, date row, color style (Full Color/Monochrome), float-across-screen |
| Second Clock | Time zone for the secondary menu bar clock |

**Reminders:** double-click any date in the popover calendar to add a reminder with a title and precise time. Days with a reminder show a pulsing dot (orange = upcoming within 24h, red = due today). Hovering a marked day shows what's scheduled. On the due day, the desktop widget and calendar both flash, and the menu bar clock pulses light/dark every 5 seconds until you check it off in the popover's "Due Today" banner.

## Project Structure

```text
FlipClock/
  App/                  App entry point and AppKit bridge (AppDelegate, FlipClockApp)
  DesktopOverlay/       Desktop overlay window, glass background, backdrop capture, content view
  FlipClock/            Split-flap rendering components (clock face, digits, flap layer, fonts)
  MenuBar/              Menu bar clock views and status item controllers
  Popover/               Popover clock, calendar, vibrant hosting controller
  Reminders/             Reminder model, store, add form, badge, due-today banner
  Settings/             Settings model (AppSettings), window, and SwiftUI view
  TimeEngine/           Tick generation and time/digit calculations
```

See `architecture.md` for the full file-by-file map.

## Architecture

- `TimeProvider` publishes clock ticks consumed across the app.
- `SplitFlapClockFace` renders the animated split-flap clock face; menu bar, popover, and desktop overlay all share this one implementation at different scales.
- `OverlayWindowController` owns the desktop overlay `NSPanel`, including size/position management and the float-across-screen drift animation.
- `WidgetGlassBackground` + `DesktopBackdropCapture` provide the widget's glass: a captured-and-blurred still of the actual desktop behind the window (real, tunable blur), falling back to live `NSVisualEffectView` vibrancy or an opaque fill (Reduce Transparency) when needed.
- `StatusItemController` owns the menu bar clock, its popover, and the reminder pulse timer.
- `AppSettings` is an `ObservableObject` that persists user preferences to `UserDefaults` and publishes changes via Combine.
- `ReminderStore` is an `ObservableObject` that persists reminders (JSON in `UserDefaults`) and is shared by reference across the popover, widget, and menu bar.

More detail — including design rationale, hard-won gotchas, and development history — lives in `architecture.md`, `design.md`, `memory.md`, and `phases.md`.

## Development Notes

- AppKit is used where SwiftUI can't reach (menu bar, window level/collection behavior, login-item registration); SwiftUI drives the settings UI and content views.
- Date and time rendering share the same split-flap face renderer for visual consistency.
- The desktop overlay window sits just above the desktop-icon layer and below normal app windows, so it's covered by any foreground app window — this is intentional, matching how system widgets behave.
- `NSWindow.frame` reports/stores whole-point origins. Any animation that accumulates a sub-pixel-per-tick offset (like the float-across-screen drift) must track its own precise position rather than reading it back from `window.frame` each tick, or the fractional progress gets silently truncated away every frame.

## Contributing

Issues and pull requests are welcome. Please keep changes scoped and run a build (`xcodebuild ... build`) before submitting.

## License

No license has been specified for this repository. All rights reserved by the author unless stated otherwise.
