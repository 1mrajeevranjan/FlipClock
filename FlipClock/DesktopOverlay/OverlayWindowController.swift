import AppKit
import SwiftUI
import Combine

/// Creates the desktop overlay window and shows/hides it in response to
/// `AppSettings.showDesktopOverlay`. Also drives the optional "float
/// across the screen" mode — a slow DVD-logo-style bounce — when enabled.
final class OverlayWindowController {
    private let window: OverlayWindow
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    private var floatTimer: Timer?
    private var floatVelocity = CGPoint(x: 0.6, y: 0.4)
    /// Exact sub-pixel drift position, tracked independently of
    /// `window.frame` — `NSWindow` truncates its reported origin to whole
    /// points, so re-deriving next tick's position from `window.frame`
    /// discards the sub-pixel remainder every time and the window never
    /// actually moves. Keeping our own precise running position and only
    /// ever writing (never reading back) `window.frame` fixes that.
    private var floatPosition: CGPoint?
    /// Top-left corner captured right before switching into full-screen
    /// mode, so leaving full-screen can restore the widget to where it
    /// actually was — the normal "pin the top-left corner" resize logic in
    /// `applySize` reads it from `window.frame`, but by the time full-screen
    /// is turned off `window.frame` IS the full-screen frame, not the
    /// widget's last real position, so without this the widget snapped to
    /// the screen's top-left corner on every exit instead of returning to
    /// its box.
    private var preFillScreenTopLeft: NSPoint?

    init(timeProvider: TimeProvider, settings: AppSettings) {
        self.settings = settings
        window = OverlayWindow()

        let hostingController = NSHostingController(rootView: OverlayContentView(timeProvider: timeProvider, settings: settings))
        window.contentViewController = hostingController

        applySize(anchorTopRight: true)
        window.setFrameAutosaveName("DesktopOverlayFrame")

        settings.$showDesktopOverlay
            .sink { [weak self] visible in
                self?.setVisible(visible)
            }
            .store(in: &cancellables)

        settings.$overlaySize
            .dropFirst()
            // `applySize` reads several `settings` properties directly
            // (including whichever one just changed) rather than using the
            // value each publisher emits. `@Published` sends from `willSet`,
            // before the new value is actually stored, so a `.sink` that
            // re-reads the same property it's reacting to synchronously
            // would see the OLD value — not a rare race, a guaranteed
            // ordering. Deferring to the next run-loop turn (by which point
            // the property write has completed) is what makes `applySize`
            // see the real, current value. This was the actual cause of the
            // "fill screen off doesn't restore the widget box" bug: the
            // resize ran once more with `fillScreen` read back as `true`,
            // sizing the window for full-screen again instead of shrinking
            // it back down.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // A size change should keep the window pinned at its
                // current top-left corner, not silently re-snap to the
                // top-right default — that default only applies on first
                // launch/before the user has ever moved it.
                self?.applySize(anchorTopRight: false)
            }
            .store(in: &cancellables)

        settings.$showDateOnOverlay
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)

        settings.$timeFormat
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)

        settings.$fillScreen
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)

        settings.$floatAcrossScreen
            .sink { [weak self] floating in
                self?.setFloating(floating)
            }
            .store(in: &cancellables)
    }

    private func applySize(anchorTopRight: Bool) {
        if settings.fillScreen, let screen = NSScreen.main {
            // Only capture on the transition into full-screen — repeated
            // calls while already full-screen (e.g. toggling "show date"
            // mid-fill) must not overwrite this with the full-screen frame.
            if preFillScreenTopLeft == nil {
                preFillScreenTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            }
            window.isMovableByWindowBackground = false
            window.hasShadow = false
            // `setFrame(_:display:)` has proven unreliable elsewhere in this
            // window's lifecycle (see `stepFloat`'s history) — drive size
            // and position through the two calls that are proven to work
            // instead of the combined one.
            window.setContentSize(screen.frame.size)
            window.setFrameOrigin(screen.frame.origin)
            return
        }
        window.isMovableByWindowBackground = true
        window.hasShadow = true

        let contentSize = OverlayContentView.windowSize(
            scale: settings.overlaySize.scale,
            showDate: settings.showDateOnOverlay,
            showMeridiem: settings.timeFormat == .twelveHour
        )
        let previousTopLeft: NSPoint
        if let savedTopLeft = preFillScreenTopLeft {
            previousTopLeft = savedTopLeft
            preFillScreenTopLeft = nil
        } else {
            previousTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        }
        window.setContentSize(contentSize)

        if anchorTopRight, let screen = NSScreen.main {
            let margin: CGFloat = 40
            let origin = NSPoint(
                x: screen.visibleFrame.maxX - contentSize.width - margin,
                y: screen.visibleFrame.maxY - contentSize.height - margin
            )
            window.setFrameOrigin(origin)
        } else {
            // Resizing an NSWindow keeps its bottom-left corner fixed by
            // default, which visually shifts the top edge down/up — pin
            // the top-left instead so an in-place size change doesn't also
            // relocate the window.
            window.setFrameOrigin(NSPoint(x: previousTopLeft.x, y: previousTopLeft.y - contentSize.height))
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }

    private func setFloating(_ floating: Bool) {
        floatTimer?.invalidate()
        floatTimer = nil

        // Dragging and auto-drift fight each other — floating mode owns
        // positioning while it's on; turning it off hands control back to
        // the user's drag.
        window.isMovableByWindowBackground = !floating
        guard floating else {
            floatPosition = nil
            return
        }

        floatPosition = window.frame.origin
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.stepFloat()
        }
        RunLoop.main.add(timer, forMode: .common)
        floatTimer = timer
    }

    private func stepFloat() {
        guard let screen = NSScreen.main, var origin = floatPosition else { return }
        let bounds = screen.visibleFrame
        let size = window.frame.size
        origin.x += floatVelocity.x
        origin.y += floatVelocity.y

        if origin.x <= bounds.minX {
            origin.x = bounds.minX
            floatVelocity.x = abs(floatVelocity.x)
        } else if origin.x + size.width >= bounds.maxX {
            origin.x = bounds.maxX - size.width
            floatVelocity.x = -abs(floatVelocity.x)
        }

        if origin.y <= bounds.minY {
            origin.y = bounds.minY
            floatVelocity.y = abs(floatVelocity.y)
        } else if origin.y + size.height >= bounds.maxY {
            origin.y = bounds.maxY - size.height
            floatVelocity.y = -abs(floatVelocity.y)
        }

        floatPosition = origin
        window.setFrameOrigin(origin)
    }
}
