# FlipClock Design System

Visual design decisions and the reasoning behind them. Implementation lives in `FlipClock/FlipClock/FlapColors.swift`, `DigitFaceRenderer.swift`, and `DesktopOverlay/WidgetGlassBackground.swift`.

## Product identity: the split-flap mechanism

Every character on every surface — digits, AM/PM, weekday, date — is rasterized as a bitmap card via `DigitFaceRenderer`, never rendered as live SwiftUI `Text`. This is deliberate, not an oversight: it's what makes the physical two-housing flip animation (`FlipCardLayer`) possible, and it's the app's core identity, not something to "simplify" toward plain text rendering.

Flip mechanics:
- Top half of a card updates the instant the value changes (in a real split-flap mechanism, the housing behind the flipping leaf already shows the upcoming value).
- Bottom half only updates once the flap finishes landing, so the new value never "peeks" early.
- Glass cards are translucent platters; the static halves are masked in sync with the flap so the value underneath never shows through mid-rotation (see `FlipCardLayer`).

## Color tokens (`FlapColors`)

- `leaf(isDark:)` — opaque card background for non-glass (menu bar) rendering.
- `glassCardFill(isDark:tone:)`, `glassGlyph(isDark:tone:)`, `glassSeparator`, `glassHinge`, `glassFlapShade` — glass-card palette, driven by `GlassTone` (`.vivid` / `.monochrome` / `.dimmed`) set once at a widget's root via `\.glassTone`. Full colour uses near-solid white (dark grey in Dark mode) card faces like the Calendar widget; Monochrome and dimmed use a faint translucent platter with soft white content, sun/moon included. Dimmed also diffuses and desaturates the glass, like macOS's own widgets while an app is in front. Automatic dimming turns vivid only when Finder is in front and every window has slid aside (wallpaper clicked) — see `DesktopFocus`.
- `digit(isDark:)` — glyph color.
- `separatorDot`, `chromeTop`/`chromeBottom`/`chromeHighlight` — pedestal/separator chrome (desktop overlay only, non-compact, `showPedestal`).

No accent/brand color token exists — the tint-customization feature was built and then fully removed; don't reintroduce a persistent accent color without an explicit new request.

## Glassmorphism (desktop widget)

Two blur strategies, used per-context:

1. **Popover** — rides on `NSPopover`'s own system vibrancy (`VibrantHostingController`, real `NSVisualEffectView(.popover)` as the top-level content view). Cards render `glassCard: true, showOwnGlassPanel: false`.
2. **Desktop widget** — `WidgetGlassBackground`, backed by `DesktopBackdropCapture`: a captured-and-Gaussian-blurred still of the **wallpaper window only** (never app windows), refreshed every 60s plus on Space/display changes, rendered as a plain `Image` clipped to the widget's rounded rect. The capture covers the **whole display**, and each widget crops the sub-rect sitting behind it, re-cropping on `NSWindow.didMoveNotification`. Capturing only the window's own rect instead meant the glass was a snapshot of wherever the widget used to be: dragging it carried the old location's wallpaper along until the next refresh, then popped. Cropping a `CGImage` doesn't copy pixels, so it's cheap enough to redo on every drag event and the glass tracks the desktop exactly while moving — which is also what makes float-across-screen's drift look right. The capture and blur are shared per display by an `actor` (deliberately not `@MainActor`, or a full-screen blur would run on the main thread), so a second widget doesn't double the cost. Falls back to a live `NSVisualEffectView(.underWindowBackground)` before the first capture lands or if Screen Recording access is denied. Falls back further to an opaque `Color(nsColor: .windowBackgroundColor)` fill when the user has Reduce Transparency enabled. Captures via `ScreenCaptureKit`'s `SCScreenshotManager`, not `CGWindowListCreateImage` — on a late-enough SDK the latter still compiles and returns a non-nil `CGImage`, but that image is a flat placeholder color, not real screen content, silently turning the whole widget into a flat opaque-looking panel with no actual desktop color/detail. Caught by dumping the raw captured `CGImage` to a PNG and looking at the actual pixels rather than trusting a non-nil return.

Why not `NSVisualEffectView` alone for the widget: its blur radius is fixed by the material and isn't a public API, so no opacity tuning can push diffusion strength past what native macOS widgets show. The captured+blurred image is the only way to get a real, tunable blur radius.

**Four things that have to be right together, or the panel stops reading as glass.**

How to measure rather than eyeball it: the Weather widget's bottom edge and the desktop widget's top edge sit over the same horizontal band of wallpaper, so a clean strip from each (no text, no flip cards — crop them and *look* before trusting the numbers) is a controlled comparison. Take mean |Laplacian| for diffusion, mean RGB for tone, `(max-min)/max` for saturation. Current match, against the wallpaper band beside them:

| | diffusion | luminance | RGB | saturation |
|---|---|---|---|---|
| native Weather widget | 1.06 | 106.2 | 139, 98, 81 | 0.416 |
| this widget | 0.88 | 107.4 | 138, 99, 85 | 0.389 |
| bare wallpaper | 4.98 | 109.1 | 139, 100, 88 | 0.366 |

1. **`clampedToExtent()` before the Gaussian.** Without it Core Image samples transparent black past the image bounds, so the blurred result's alpha falls off towards every edge — measured ~52% in the outer 10px against ~99% in the middle. On screen the widget's whole rim went semi-transparent and leaked the sharp, unblurred desktop through exactly where the frosted edge belongs.
2. **Capture at `screen.backingScaleFactor`, not in points.** A point-sized request hands back a half-resolution backdrop that gets upscaled 2x into the widget, and that upscale smooths away more detail than the Gaussian does — which is why shrinking the blur radius appeared to do nothing until this was fixed. The radius is in pixels, so it scales with the image.
3. **Saturation above 1** (`WidgetGlassBackground.vibrancy`). The one that matters most and is least obvious: `NSVisualEffectView` materials don't just blur, they run the backdrop hotter than the desktop behind it (0.42 against the wallpaper's 0.37 here). Passing it through at saturation 1 is what left this looking like a flat grey-brown panel — a blurry screenshot of the wallpaper rather than vibrant glass.
4. **A slight dark scrim** (`WidgetGlassBackground.scrim`). Counter-intuitively *dark*, not white: measured against the wallpaper beside it, native widget glass comes out level with or slightly below the desktop, never lifted. A white scrim — the obvious choice for "frosted" — pushed the panel to luminance 142 against native's 110.

Don't over-blur chasing "frostiness". The wallpaper's large-scale structure is supposed to stay readable through the glass; native widgets only drop diffusion from ~5.0 to ~1.1, not to zero. Blurring until the backdrop is a uniform wash is what makes a panel read as opaque plastic instead of glass.

**Corner radius formula:** `(34 * scale).clamped(to: 14...40)`, `0` in full-screen mode. Tracks `overlaySize` per Apple's Widget HIG guidance that a widget's corner radius should scale with its container rather than stay a flat constant.

**Padding formula:** `(16 * scale).clamped(to: 11...22)` — HIG's standard 16pt widget margin, scaled and clamped so the smallest widget size doesn't crowd its edges.

**Shadow:** two layered SwiftUI `.shadow()` calls (a soft ambient one + a tighter contact one), both scaled by `overlaySize`. The native `NSWindow` shadow is always off — it follows the window's rectangular bounds, not the rounded content, and produced a visible square edge past the rounded corners.

**Glossy rim:** an `AngularGradient` stroke, bright arc along the top curve fading to the sides — mimics light catching a curved glass edge from above. Deliberately *not* a flat stroke drawn all the way around (an earlier attempt at that read as an artificial ring).

## App controls and settings

- Settings uses a compact, resizable sidebar window without repeated branding or page headings. Labels share a leading column; switches, pickers and buttons share a trailing control column. The window fits the measured page content without animation, capped to the screen height; long pages scroll. The previous sliding-pill workaround is no longer used.
- The 196pt sidebar uses individual rounded navigation cards with hover and selection states, plus ⌘1–⌘4 shortcuts. A 700pt minimum window width preserves the settings control area. The title bar has no separator and shares the content's adaptive window background.
- General, Appearance and Desktop Clock share a still preview rendered by `SplitFlapClockFace`, without creating another time provider.
- The popover starts directly with compact icon-and-label tool controls, without branding or a Settings header. Settings remains in the menu-bar clock's context menu. Calendar dates are keyboard-focusable buttons with a visible Add Reminder action. The reminder form stays inline in an inset card, with shared leading/trailing edges and no reserved calendar height.
- Popover controls use native Liquid Glass on macOS 26+, grouped in a single `GlassEffectContainer`, with adaptive fills on older systems. Calendar uses the system accent, timer orange, and stopwatch teal; labels remain primary-colored for contrast. Content cards stay lightly tinted on the existing popover vibrancy rather than adding blur layers. Tab/calendar/form changes animate only opacity, scale and a small vertical offset with a low-bounce spring; window sizing settles immediately, and Reduce Motion removes these transforms. The material consumes the newly published theme value directly so theme changes have no one-selection delay.
- The timer wheel's selected values and unit labels are foreground content of one clear capsule of glass. A native Canvas draws cylindrical refraction in pixel-high slices, using explicit light/dark ink: 2.55× at the center, tapering to normal sampling at the rim. The 54pt numeric viewport accommodates magnified two-digit values. This avoids the filtered-shader/vibrancy composition path that could drop selected digits on screen. The glyph font size stays 16pt; the distortion changes the drawn image. Reels glide between values in 180ms. Foreground and surrounding rows share positions with complementary clipping; unit labels stay undistorted and aligned. The focused unit label becomes primary-colored and semibold, preserving a keyboard focus cue without a blue rectangle. The glass row does not intercept input, and Reduce Motion disables reel movement. Rendering regression tests check visible ink and magnification in both themes, including intermediate scroll positions. Add Reminder uses the same large prominent capsule treatment as the timer's primary action.
- The calendar heading is plain clickable text without button chrome or a disclosure arrow. Clicking moves from days to months to pages of 12 years. Empty popover space steps back from years to months, then to today's calendar; the same back action is available to accessibility users. Arrows step through the visible level; choosing a year returns to months, and choosing a month returns to dates. Day grids use only the weeks needed for the month, and the popover fits its current content. Timer and stopwatch retain consistent action sizing; each tool observes its own updates so stopwatch ticks do not invalidate the popover root.
- Stopwatch hundredths pass their known cadence into the flip layer, so the first flip and flips after a pause don't wait for timing estimates to settle. Other clock cards keep automatic pacing.
- Time-zone choices snapshot offsets once per presentation. Search accepts both city names with spaces and IANA identifiers; Choose commits and Cancel leaves preferences unchanged.

## Typography

- `WidgetFont` catalog: 37 bundled decorative fonts (`Fonts/`), each entry carrying a real CoreText-resolved PostScript name (not a filename guess — several files' internal names don't match their filenames at all).
- Font size within a card: shrink-to-fit starting at `fullSize.height * 0.78`, stepping down until the rendered width fits `fullSize.width * 0.82`.
- No live-measured text anywhere in the clock rendering path — every glyph is pre-rasterized, which is also why font swaps require re-rendering (handled by `DigitFaceRenderer`'s cache keys including a font identifier).

## Reminder visual language

- **Badge (`ReminderBadge`):** small pulsing dot on calendar day cells. Red = due today and unacknowledged. Orange = landing within the next 24 hours.
- **Menu bar theme and pulse:** primary and world clocks receive an explicit resolved light/dark value because status-item hosting doesn't reliably propagate preferred appearance. Due reminders alternate the primary clock's opacity every 5s, preserving the selected theme.
- **"Due Today" banner:** red-tinted rounded card in the popover, one row per reminder with an "@ time" + title + acknowledge checkmark.
- **Desktop reminder footer:** two rows below the clock/date, sorted by time and formatted “Today @ time – reminder”, with an additional-count row when needed. Two-line text and tooltips preserve readability at small widget sizes. Future reminders are orange; elapsed reminders are red, with the widget's monochrome/dimmed tone taking precedence. Window sizing includes the footer and refreshes at day/time-zone changes.
- **Timed alerts:** `ReminderNotifications` schedules native UserNotifications requests with stable reminder IDs. Sound selection lives in General settings; a build phase copies the system AIFF sounds into the app before signing so the notification service can play them after the app exits. Pending requests are reconciled after edits, sound changes and acknowledgements; foreground alerts opt into banner/list/sound presentation. Dismiss and the native close action acknowledge the matching reminder, clear its pending/delivered alert and remove its active UI entry. The delegate/category register before launch finishes so actions also work after a cold launch. macOS permission and sound settings remain authoritative; system notification audio is one-shot and has no public mid-playback stop API.
- **"@ time" convention:** every place a reminder's precise time is shown (add form, hover preview, due-today banner) uses the literal `@ <time>` prefix rather than a label like "at" or "Time:" — compact and consistent across all three surfaces.

## Accessibility

- **Reduce Transparency:** widget and popover fall back to opaque fills. The popover follows live accessibility display changes; controls also strengthen outlines with Increase Contrast. New popover transitions and press feedback respect Reduce Motion; the existing flip-card/desktop-drift behavior is unchanged.
- No custom Reduce Motion handling yet for the flip animation or float-across-screen drift — flagged as open in `phases.md`, deliberately not touched without an explicit decision since the flip animation is the product's core identity, not just decoration.

## Anti-patterns already tried and reverted

Don't reintroduce these without a specific reason — see `memory.md` for the full story:
- Stacking `.ultraThinMaterial` on top of the live desktop blur (washed the panel to opaque white).
- A flat stroke drawn all the way around the widget's rounded rect (read as an artificial ring, not a glass edge).
- Native `NSWindow.hasShadow` for the widget (produces a square-edge artifact past rounded corners).
