# FlipClock

FlipClock is a macOS split-flap clock app with a menu bar clock, a full popover view, a desktop overlay, and a configurable settings window.

## Features

- Menu bar clock with live split-flap animation
- Full popover clock with calendar and date header
- Desktop overlay clock that can sit on the desktop or float across the screen
- Optional second menu bar clock in a different time zone
- Configurable appearance, time format, overlay size, and AM/PM style
- Launch-at-login support
- Automatic settings window sizing per tab

## Requirements

- macOS 14.0 or later
- Xcode 16 or later

## Build

Open `FlipClock.xcodeproj` in Xcode and build the `FlipClock` scheme.

Or build from the command line:

```bash
xcodebuild -project FlipClock.xcodeproj \
  -scheme FlipClock \
  -configuration Debug \
  build
```

## Run

Run the app from Xcode, or launch the built app bundle directly from DerivedData.

The app is an `LSUIElement` menu bar app, so it does not show a Dock icon.

## Project Setup

The project is defined in `project.yml` and the generated Xcode project is checked in at `FlipClock.xcodeproj`.

## Settings

FlipClock settings are grouped into four tabs:

- General
- Appearance
- Desktop Clock
- Second Clock

The settings window is designed to resize per tab instead of leaving excess blank space.

## Repository Structure

```text
FlipClock/
  App/                  App entry point and AppKit bridge
  DesktopOverlay/       Desktop clock window and content
  FlipClock/            Split-flap rendering components
  MenuBar/              Menu bar clock views and controllers
  Popover/              Popover clock and calendar UI
  Settings/             Settings model, window, and SwiftUI view
  TimeEngine/           Tick and time calculations
```

## How It Works

- `TimeProvider` publishes clock ticks used across the app.
- `SplitFlapClockFace` renders the animated clock faces.
- `OverlayWindowController` manages the desktop overlay window.
- `StatusItemController` owns the menu bar clock and popover.
- `AppSettings` stores user preferences in `UserDefaults`.

## Development Notes

- The app uses AppKit where needed for menu bar, window, and login-item behavior.
- SwiftUI is used for the settings UI and content views.
- Date and time rendering share the same split-flap face renderer for consistency.

## License

No license has been specified for this repository.
