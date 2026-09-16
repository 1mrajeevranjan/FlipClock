import AppKit
import SwiftUI
import Combine

/// Creates the second desktop clock widget — same borderless/desktop-level
/// `OverlayWindow` and glass treatment as the primary clock's
/// `OverlayWindowController`, but pinned to `settings.secondTimezoneID` and
/// labeled with that timezone. Deliberately skips the primary widget's
/// float-across-screen/fill-screen modes — this is a companion widget, not
/// the main clock.
final class SecondClockOverlayWindowController {
    private let window: OverlayWindow
    private let settings: AppSettings
    private let backdropCapture = DesktopBackdropCapture()
    private var cancellables = Set<AnyCancellable>()

    init(timeProvider: TimeProvider, settings: AppSettings) {
        self.settings = settings
        window = OverlayWindow()

        let hostingController = NSHostingController(
            rootView: SecondClockOverlayContentView(timeProvider: timeProvider, settings: settings, backdropCapture: backdropCapture)
        )
        window.contentViewController = hostingController

        applySize(anchorTopRight: true)
        window.setFrameAutosaveName("SecondClockOverlayFrame")

        settings.$showSecondClockOverlay
            .sink { [weak self] visible in
                self?.setVisible(visible)
            }
            .store(in: &cancellables)

        settings.$overlaySize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySize(anchorTopRight: false)
                self?.startBackdropCaptureIfNeeded()
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

        // The timezone label is now rendered as its own row of flip cards
        // (see `SecondClockOverlayContentView.TimezoneFlapRow`) — its width
        // varies with the chosen timezone's city name, so a new selection
        // needs the window resized same as any other layout-affecting
        // setting change.
        settings.$secondTimezoneID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySize(anchorTopRight: false) }
            .store(in: &cancellables)
    }

    private func applySize(anchorTopRight: Bool) {
        window.isMovableByWindowBackground = true
        window.hasShadow = false

        let contentSize = SecondClockOverlayContentView.windowSize(
            scale: settings.overlaySize.scale,
            showDate: settings.showDateOnOverlay,
            showMeridiem: settings.timeFormat == .twelveHour,
            timezoneLabel: SecondClockOverlayContentView.timezoneLabel(for: settings.secondTimezoneID)
        )
        let previousTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(contentSize)

        if anchorTopRight, let screen = NSScreen.main {
            let margin: CGFloat = 40
            // Offset further left than the primary widget's default spot
            // so first launch doesn't stack the two windows on top of
            // each other.
            let origin = NSPoint(
                x: screen.visibleFrame.maxX - contentSize.width - margin - 260,
                y: screen.visibleFrame.maxY - contentSize.height - margin
            )
            window.setFrameOrigin(origin)
        } else {
            window.setFrameOrigin(NSPoint(x: previousTopLeft.x, y: previousTopLeft.y - contentSize.height))
        }
        maskContentView(cornerRadius: WidgetGlassBackground.cornerRadius(scale: settings.overlaySize.scale))
    }

    private func maskContentView(cornerRadius: CGFloat) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            window.orderFront(nil)
            startBackdropCaptureIfNeeded()
            settings.startWatchingSystemWidgetAppearance()
        } else {
            window.orderOut(nil)
            backdropCapture.stop()
            if !settings.showDesktopOverlay { settings.stopWatchingSystemWidgetAppearance() }
        }
    }

    private func startBackdropCaptureIfNeeded() {
        guard settings.showSecondClockOverlay else {
            backdropCapture.stop()
            return
        }
        // Tuned against real macOS widget glass by measuring high-frequency
        // detail energy in screenshots: at 30pt the backdrop washed out to a
        // flat colour field (energy ~0.34) while Notification Center's own
        // widgets sit around 1.0-1.7, still showing the wallpaper's large-scale
        // structure through the frost. ~16pt lands in that range.
        let blurRadius = (4 * settings.overlaySize.scale).clamped(to: 2.5...8)
        backdropCapture.start(window: window, blurRadius: blurRadius)
    }
}
