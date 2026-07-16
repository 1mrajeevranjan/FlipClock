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
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)

        settings.$timeFormat
            .dropFirst()
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)

        settings.$floatAcrossScreen
            .sink { [weak self] floating in
                self?.setFloating(floating)
            }
            .store(in: &cancellables)
    }

    private func applySize(anchorTopRight: Bool) {
        let contentSize = OverlayContentView.windowSize(
            scale: settings.overlaySize.scale,
            showDate: settings.showDateOnOverlay,
            showMeridiem: settings.timeFormat == .twelveHour
        )
        let previousTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
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
        guard floating else { return }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.stepFloat()
        }
        RunLoop.main.add(timer, forMode: .common)
        floatTimer = timer
    }

    private func stepFloat() {
        guard let screen = NSScreen.main else { return }
        let bounds = screen.visibleFrame
        var frame = window.frame
        var origin = frame.origin
        origin.x += floatVelocity.x
        origin.y += floatVelocity.y

        if origin.x <= bounds.minX {
            origin.x = bounds.minX
            floatVelocity.x = abs(floatVelocity.x)
        } else if origin.x + frame.width >= bounds.maxX {
            origin.x = bounds.maxX - frame.width
            floatVelocity.x = -abs(floatVelocity.x)
        }

        if origin.y <= bounds.minY {
            origin.y = bounds.minY
            floatVelocity.y = abs(floatVelocity.y)
        } else if origin.y + frame.height >= bounds.maxY {
            origin.y = bounds.maxY - frame.height
            floatVelocity.y = -abs(floatVelocity.y)
        }

        frame.origin = origin
        window.setFrame(frame, display: true)
    }
}
