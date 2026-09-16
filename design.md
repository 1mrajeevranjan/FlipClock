# FlipClock Design System

Visual design decisions and the reasoning behind them. Implementation lives in `FlipClock/FlipClock/FlapColors.swift`, `DigitFaceRenderer.swift`, and `DesktopOverlay/WidgetGlassBackground.swift`.

## Product identity: the split-flap mechanism

Every character on every surface — digits, AM/PM, weekday, date — is rasterized as a bitmap card via `DigitFaceRenderer`, never rendered as live SwiftUI `Text`. This is deliberate, not an oversight: it's what makes the physical two-housing flip animation (`FlipCardLayer`) possible, and it's the app's core identity, not something to "simplify" toward plain text rendering.

Flip mechanics:
- Top half of a card updates the instant the value changes (in a real split-flap mechanism, the housing behind the flipping leaf already shows the upcoming value).
- Bottom half only updates once the flap finishes landing, so the new value never "peeks" early.
- The animating flap always renders opaque, even in glass mode — it has to fully mask the static digit underneath mid-rotation or the old value ghosts through.

## Color tokens (`FlapColors`)

- `leaf(isDark:)` — opaque card background for non-glass (menu bar) rendering.
- `frostedCard(isDark:)` — opaque "frosted glass" tone shared by both the resting glass-mode card and its flap, so a flip never visibly changes the card's own appearance.
- `digit(isDark:)` — glyph color.
- `separatorDot`, `chromeTop`/`chromeBottom`/`chromeHighlight` — pedestal/separator chrome (desktop overlay only, non-compact, `showPedestal`).

No accent/brand color token exists — the tint-customization feature was built and then fully removed; don't reintroduce a persistent accent color without an explicit new request.

## Glassmorphism (desktop widget)

Two blur strategies, used per-context:

1. **Popover** — rides on `NSPopover`'s own system vibrancy (`VibrantHostingController`, real `NSVisualEffectView(.popover)` as the top-level content view). Cards render `glassCard: true, showOwnGlassPanel: false`.
2. **Desktop widget** — `WidgetGlassBackground`, backed by `DesktopBackdropCapture`: a captured-and-Gaussian-blurred still of the actual desktop behind the window, refreshed every 5s, rendered as a plain `Image` clipped to the widget's rounded rect. Falls back to a live `NSVisualEffectView(.underWindowBackground)` before the first capture lands or if Screen Recording access is denied. Falls back further to an opaque `Color(nsColor: .windowBackgroundColor)` fill when the user has Reduce Transparency enabled. Captures via `ScreenCaptureKit`'s `SCScreenshotManager`, not `CGWindowListCreateImage` — on a late-enough SDK the latter still compiles and returns a non-nil `CGImage`, but that image is a flat placeholder color, not real screen content, silently turning the whole widget into a flat opaque-looking panel with no actual desktop color/detail. Caught by dumping the raw captured `CGImage` to a PNG and looking at the actual pixels rather than trusting a non-nil return.

Why not `NSVisualEffectView` alone for the widget: its blur radius is fixed by the material and isn't a public API, so no opacity tuning can push diffusion strength past what native macOS widgets show. The captured+blurred image is the only way to get a real, tunable blur radius.

**Three things that have to be right together, or the panel stops reading as glass.** Each was found by measuring screenshots against real Notification Center widgets (mean |Laplacian| over the glass, masking out the flip cards, as a stand-in for "how diffuse does this look"; native widgets sit around 1.0–1.7):

1. **`clampedToExtent()` before the Gaussian.** Without it Core Image samples transparent black past the image bounds, so the blurred result's alpha falls off towards every edge — measured ~52% in the outer 10px against ~99% in the middle. On screen the widget's whole rim went semi-transparent and leaked the sharp, unblurred desktop through exactly where the frosted edge belongs.
2. **Capture at `screen.backingScaleFactor`, not in points.** A point-sized request hands back a half-resolution backdrop that gets upscaled 2x into the widget, and that upscale smooths away more detail than the Gaussian does — which is why shrinking the blur radius appeared to do nothing until this was fixed. The radius is in pixels, so it scales with the image.
3. **A translucent scrim over the blur** (`WidgetGlassBackground.scrim`). Blurred wallpaper on its own reads as dark smoked glass; macOS's widgets lay a scrim over theirs, which is what produces the milky lift and keeps content legible over a dark wallpaper. A flat white/black pair rather than a SwiftUI `Material` — see the anti-patterns below for why.

**Corner radius formula:** `(34 * scale).clamped(to: 14...40)`, `0` in full-screen mode. Tracks `overlaySize` per Apple's Widget HIG guidance that a widget's corner radius should scale with its container rather than stay a flat constant.

**Padding formula:** `(16 * scale).clamped(to: 11...22)` — HIG's standard 16pt widget margin, scaled and clamped so the smallest widget size doesn't crowd its edges.

**Shadow:** two layered SwiftUI `.shadow()` calls (a soft ambient one + a tighter contact one), both scaled by `overlaySize`. The native `NSWindow` shadow is always off — it follows the window's rectangular bounds, not the rounded content, and produced a visible square edge past the rounded corners.

**Glossy rim:** an `AngularGradient` stroke, bright arc along the top curve fading to the sides — mimics light catching a curved glass edge from above. Deliberately *not* a flat stroke drawn all the way around (an earlier attempt at that read as an artificial ring).

## Typography

- `WidgetFont` catalog: 37 bundled decorative fonts (`Fonts/`), each entry carrying a real CoreText-resolved PostScript name (not a filename guess — several files' internal names don't match their filenames at all).
- Font size within a card: shrink-to-fit starting at `fullSize.height * 0.78`, stepping down until the rendered width fits `fullSize.width * 0.82`.
- No live-measured text anywhere in the clock rendering path — every glyph is pre-rasterized, which is also why font swaps require re-rendering (handled by `DigitFaceRenderer`'s cache keys including a font identifier).

## Reminder visual language

- **Badge (`ReminderBadge`):** small pulsing dot. Red = due today and unacknowledged. Orange = landing within the next 24 hours. Used identically on calendar day cells (5pt) and the desktop widget's top-trailing corner badge (8–16pt, scaled).
- **Menu bar pulse:** the whole compact clock face alternates light/dark theme rendering every 5s while something's due today and unacknowledged — a deliberately subtle, ambient nudge rather than a badge/banner/notification, per the original request ("very subtle way to remind the user").
- **"Due Today" banner:** red-tinted rounded card in the popover, one row per reminder with an "@ time" + title + acknowledge checkmark.
- **"@ time" convention:** every place a reminder's precise time is shown (add form, hover preview, due-today banner) uses the literal `@ <time>` prefix rather than a label like "at" or "Time:" — compact and consistent across all three surfaces.

## Accessibility

- **Reduce Transparency:** widget falls back to an opaque fill; popover's glassiness slider gets overridden to fully opaque (the OS accommodation wins over the per-app preference, not blended with it).
- No custom Reduce Motion handling yet for the flip animation or float-across-screen drift — flagged as open in `phases.md`, deliberately not touched without an explicit decision since the flip animation is the product's core identity, not just decoration.

## Anti-patterns already tried and reverted

Don't reintroduce these without a specific reason — see `memory.md` for the full story:
- Stacking `.ultraThinMaterial` on top of the live desktop blur (washed the panel to opaque white).
- A flat stroke drawn all the way around the widget's rounded rect (read as an artificial ring, not a glass edge).
- Native `NSWindow.hasShadow` for the widget (produces a square-edge artifact past rounded corners).
