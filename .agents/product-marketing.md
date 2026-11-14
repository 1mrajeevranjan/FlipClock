# Product Marketing Context

*Last updated: 2026-11-14*

## Product Overview
**One-liner:** A real split-flap clock for your Mac — in the menu bar, in a popover, and on your desktop.
**What it does:** ClackClock puts an animated flip clock in three places: a compact menu bar clock, a popover with a calendar, timer and stopwatch, and a desktop widget that sits beside macOS's own widgets. Reminders ring on time with their own banner and sound, and up to five world clocks can live in the menu bar or on the desktop.
**Product category:** Mac menu bar clock / desktop clock widget (App Store category: Utilities).
**Product type:** Native macOS app (Swift, SwiftUI + AppKit), Mac App Store.
**Business model:** TBD (paid upfront, free, or freemium — not decided).

## Target Audience
**Target companies:** Individual Mac users (B2C).
**Decision-makers:** The user themself.
**Primary use case:** See the time, date and what's next at a glance, beautifully, without opening an app.
**Jobs to be done:**
- Make my desktop feel personal and calm — a clock I enjoy looking at.
- Keep today's reminders and the calendar one click away in the menu bar.
- Time focus sessions and track time zones without juggling separate apps.
**Use cases:**
- Pomodoro / focus timer from the menu bar.
- Remote workers tracking teammates' time zones (Tokyo, London, New York widgets).
- Full-screen flip clock on a second display or while presenting.
- Lightweight personal reminders ("Design review @ 4:30 PM") that actually interrupt you on time.

## Personas
B2C — single user; no buying committee.

## Problems & Pain Points
**Core problem:** The macOS clock is a tiny line of text; good-looking clocks are screensavers you can't work with, and time/calendar/timer/world-clock tools are scattered across several apps.
**Why alternatives fall short:**
- Flip-clock screensavers only run when you're away from the Mac.
- Menu bar calendar and world-clock utilities are text-only and look utilitarian.
- Native notifications can arrive late, so reminders slip by.
**What it costs them:** Context switching between apps; missed reminders; a desktop that feels generic.
**Emotional tension:** Wanting a workspace that feels crafted and personal without adding clutter or battery drain.

## Competitive Landscape
**Direct:** Other flip-clock apps and screensavers — mostly screensavers or single-window apps, not a menu bar + popover + widget system.
**Secondary:** Menu bar calendar / world-clock utilities — functional but plain text, no flip animation, separate apps for timer and reminders.
**Indirect:** macOS's built-in menu bar clock and desktop widgets — free and native, but small, non-animated and not customisable.

## Differentiation
**Key differentiators:**
- Every character is a real flip card with a two-leaf flip animation — not styled text.
- One app covers clock, calendar, reminders, timer, stopwatch and world clocks.
- Desktop widget with true frosted glass that blurs your actual wallpaper and dims like native widgets.
- Deep customisation: card colours, frosted glass, fonts, light/dark, 12/24-hour, sizes up to fill-screen.
- Private and light: no network requests, no data collected, near-zero CPU at idle.
**How we do it differently:** Native Swift/Core Animation rendering with careful power management (pauses work when the widget is covered).
**Why that's better:** Looks like a physical object on your desk, costs almost nothing in battery.
**Why customers choose us:** It's the clock they actually want to look at — and it replaces three small utilities.

## Objections
| Objection | Response |
|-----------|----------|
| "macOS already has a clock." | ClackClock adds the calendar, reminders, timer, stopwatch and world clocks — and makes the clock something you enjoy seeing. |
| "Will it drain my battery?" | Idle CPU is near zero; the widget stops working while it's covered and slows down in Low Power Mode. |
| "Why does it ask for Screen Recording?" | Only to blur the wallpaper behind the widget for real frosted glass. Optional — it works without it. Nothing leaves your Mac. |

**Anti-persona:** People who want a full calendar/task manager (sync, shared calendars, recurring tasks) — ClackClock is a clock with lightweight reminders.

## Switching Dynamics
**Push:** The default clock is tiny and boring; reminders arrive late.
**Pull:** A beautiful flip clock everywhere, plus timer, stopwatch and world clocks in one place.
**Habit:** Already using a menu bar calendar or world-clock app.
**Anxiety:** Battery cost, permissions, clutter.

## Customer Language
**How they describe the problem:**
- "I want a clock on my desktop that actually looks good."
**How they describe us:**
- "Like an old train-station flip board on my Mac."
**Words to use:** flip clock, split-flap, at a glance, on your desktop, in your menu bar, frosted glass, private, lightweight, native.
**Words to avoid:** "Apple widget" (trademark), "screensaver", third-party brand/font names.
**Glossary:**
| Term | Meaning |
|------|---------|
| Split-flap | Mechanical flip-card display (train-station board style) |
| Widget | ClackClock's desktop clock window |
| Fill screen | Clock grows to fill the space between menu bar and Dock |
| Frosted glass | Translucent cards that blur what's behind them |

## Brand Voice
**Tone:** Warm, crafted, quietly confident.
**Style:** Short, concrete sentences; show, don't hype.
**Personality:** Tactile, nostalgic, polished, calm, private.

## Proof Points
**Metrics:** No network requests; no data collected; idle CPU ≈ 0.4%; 129 automated tests.
**Customers:** None yet (pre-launch).
**Testimonials:** None yet.
**Value themes:**
| Theme | Proof |
|-------|-------|
| Beautiful | Real flip-card rendering, frosted glass, 9 card colours |
| All-in-one | Clock, calendar, reminders, timer, stopwatch, world clocks |
| Respectful | No tracking, no network, near-zero battery at idle |

## Goals
**Business goal:** Launch on the Mac App Store.
**Conversion action:** Download from the Mac App Store.
**Current metrics:** Pre-launch.

---

## App Store Listing (draft)

**Name (≤30):** ClackClock
**Subtitle (≤30):** Split-flap clock for your Mac

**Promotional text (≤170):**
A real flip clock in your menu bar and on your desktop — with a calendar, reminders that ring on time, a timer, a stopwatch and world clocks.

**Description:**
ClackClock brings the charm of a split-flap display to your Mac. Every digit is a real flip card that turns over with a satisfying two-leaf animation — in your menu bar, in a handy popover, and on your desktop.

MENU BAR CLOCK
• A live flip clock right in your menu bar
• Click it for your calendar, timer and stopwatch
• Right-click for Settings and Quit

CALENDAR & REMINDERS
• Month calendar in the popover — browse months and years in a click
• Add a reminder to any day with an exact time (double-click a day or press ⌘N)
• Days with reminders get badges: orange when one is coming up, red when it's due today
• A "Due Today" list keeps the day's reminders in view
• Reminders ring on time with their own banner and your chosen alert sound
• Missed one while your Mac was asleep? It rings when you wake it

TIMER & STOPWATCH
• Set a countdown with smooth hour, minute and second wheels
• Watch the time flip down — it keeps exact time even when the popover is closed
• Count-up stopwatch with start, stop and reset

DESKTOP WIDGET
• A flip clock that sits right beside your desktop widgets
• Four sizes, from compact to 3×
• Fill Screen turns your whole desktop into a giant flip clock
• Float Across Screen lets the clock drift slowly around your desktop
• Optional date row and your next reminders, right on the widget
• Frosted-glass background that blurs your actual wallpaper
• Dims when an app is in front and lights up when you're on the desktop, just like native widgets

WORLD CLOCKS
• Add up to five time zones
• Show each one in the menu bar, as its own desktop widget, or both
• Give them names — "Tokyo office", "Mom" — with their own size and 12/24-hour format

MAKE IT YOURS
• Nine card colours, plus Monochrome
• Frosted-glass cards that keep a hint of colour
• A collection of decorative digit fonts
• Light, Dark or System appearance
• 12-hour or 24-hour time, with AM/PM text or a sun/moon icon
• Pick any built-in macOS alert sound for reminders
• Launch at login (off until you turn it on)

BUILT FOR THE MAC
• Native app, written in Swift
• Lightweight: near-zero CPU when idle; pauses while the widget is covered and slows down in Low Power Mode
• Supports Reduce Motion, Reduce Transparency and VoiceOver
• No account, no tracking, no network requests — nothing leaves your Mac

Screen Recording permission is optional and only used to blur the wallpaper behind the desktop widget. Without it, ClackClock uses standard macOS vibrancy instead.

**Keywords (≤100, name/subtitle words already indexed):** flip,desktop,widget,menu bar,retro,timer,stopwatch,reminder,calendar,world time,zone,countdown

**Screenshot captions:**
Images: `marketing/screenshots/captioned/` (with headlines) and `plain/` (raw), 2880×1800. Retaken 2026-11-15 on the 1.1.0 build.
1. A real flip clock for your Mac
2. Your calendar, one click away
3. Never miss a reminder
4. Set a timer in seconds
5. Every time zone you care about
6. Pick the face you love
7. Frosted glass, nine colours
8. Beautiful in light and dark
