# Regression and stress results — 2026-10-19

## Popover bug regression — October 19

114 tests passed with zero failures after the first-open button, calendar selection, and sound guards changed. The 34 focused calendar/timer/notification/rendering checks also passed.

- The inactive first-render check reproduced a gray Add Reminder action before the fix. It now renders blue immediately, without another interaction.
- Opening the popover selects the current date and month. Midnight and time-zone changes refresh calendar state; deliberate browsing remains intact during same-day refreshes. Only the selected day receives a filled selection circle.
- Foreground notification presentation requires a matching, unacknowledged reminder whose scheduled second has arrived. Unknown, deleted, acknowledged, and future reminders cannot request sound.
- Countdown tests now inject silent audio callbacks. Idle, paused, and reset countdowns emit no sound callback; an actual completion emits exactly one. Earlier regression runs used real macOS chimes. This confirms a test-audio source, but does not establish the sole cause of the reported live sound.

Evidence: `/tmp/flipclock-popup-bugs-regression.log` and `/var/folders/2c/ds4y85f53p7cps19pr2s87gc0000gn/T/FlipClock-DerivedData/Logs/Test/Test-FlipClock-2026.10.19_12-10-33-+0530.xcresult`.

Live popover interaction and speaker output remain unverified under the Computer Use restriction described below.

## Previous stress run — October 18

110 tests passed in each of three fresh-process runs: 330 test executions, zero failures. Debug configuration, native macOS destination, Xcode 27.

```sh
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO -test-iterations 3 \
  -test-repetition-relaunch-enabled YES test
```

The original 100-test suite passed before additional regression cases were added. Two new countdown tests reproduced failures before the fixes and passed afterward.

Evidence on the development machine:

- Log: `/tmp/flipclock-regression-stress-3x.log`
- Result bundle: `/var/folders/2c/ds4y85f53p7cps19pr2s87gc0000gn/T/FlipClock-DerivedData/Logs/Test/Test-FlipClock-2026.10.18_23-22-10-+0530.xcresult`

## Fixes

- Repeated Start no longer replaces an active countdown's displayed duration while leaving its original deadline in effect.
- Reopening the timer just before completion no longer postpones its alarm. Display ticks remain aligned to the original deadline.
- The primary menu-bar item sizes itself from the newly emitted 12/24-hour format, avoiding the old value sent during `@Published`'s `willSet`.
- Acknowledged reminders disappear from calendar badges and hover details as well as the widget and due-today banner. Acknowledgment history remains persisted.
- Reminder emphasis refreshes after day/time-zone changes and waking, and stops when yesterday's reminder is no longer due today.
- Tips and FAQ have native help-dialog handlers. Support & Feedback, Website, Rate App, Share App, and More Apps remain disabled with explanatory tooltips because destinations have not been configured.

## Automated coverage

| Area | Checks |
| --- | --- |
| Countdown | Start, repeated Start, pause/resume/reset, zero duration, completion, hidden operation, reopening near the deadline, rapid cycles |
| Stopwatch and tabs | Start/stop/reset, accumulated time, centiseconds, first-flip pacing, close/reopen, tab switching, zero hidden display updates after 1,000 mixed cycles |
| Calendar | Day/month/year navigation, previous/next, empty-space back behavior at model level, year bounds, leap years, complete grids across 4,800 months, 9,600 forward/back page moves |
| Settings and world clocks | All theme/font/size/format/meridiem/colour/sound choices, desktop/date/fill/float state, add/remove/display modes, five-clock limit, persistence during 300 cycles, time-zone search and ordering |
| Reminders | Add/remove/acknowledge/bulk acknowledge, persistence, badges/details cleanup, sorted widget details, 500-record stress, notification identities/triggers/sounds, dismiss-handler behavior |
| Rendering and resources | Light/dark magnifier ink and intermediate positions, two-digit clipping, bitmap-cache reuse, local-midnight date changes, concurrent capture deduplication, every bundled font, icon resolution |
| Component actions | 1,000 direct arrow-key events to the timer's native input component; enabled More-menu selectors have handlers; unconfigured commands are disabled |

The compiled icon catalog contains renditions from 16×16 through 1024×1024. Larger renditions are in `Assets.car`; the compiler's legacy `.icns` does not contain every catalog size.

## Live checks still required

Computer Use returned **“Computer Use was not approved to use FlipClock.”** No live click-through was performed or substituted through another automation tool. Passing model/component tests does not establish that every visible button was clicked successfully.

- Open/close the popover and Settings; switch all tabs and verify pointer targets, focus, keyboard shortcuts, alignment and animation.
- Exercise calendar heading/arrows/back gestures; submit and cancel reminders, including blank titles; choose and cancel time-zone changes.
- Check timer scrolling/focus, magnification, Start/Pause/Resume/Reset/Done and stopwatch Start/Pause/Resume/Reset in the actual popover.
- Check desktop dragging, context-menu Settings/Hide, show/hide, size/date/format, fill-screen and floating transitions.
- Verify login-item registration and notification permission states without disturbing existing user configuration.
- Listen to sound previews and a delivered macOS reminder, then dismiss it and verify native notification removal. Automated tests validate resources, requests and the dismissal handler, not speaker output or Notification Center delivery.
- Open About/Tips/FAQ; configure and verify the five external destinations before enabling those commands.
