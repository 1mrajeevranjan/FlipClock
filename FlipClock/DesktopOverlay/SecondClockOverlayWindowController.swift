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
    }

    private func applySize(anchorTopRight: Bool) {
        window.isMovableByWindowBackground = true
        window.hasShadow = false

        let contentSize = SecondClockOverlayContentView.windowSize(
            scale: settings.overlaySize.scale,
            showDate: settings.showDateOnOverlay,
            showMeridiem: settings.timeFormat == .twelveHour
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
        } else {
            window.orderOut(nil)
            backdropCapture.stop()
        }
    }

    private func startBackdropCaptureIfNeeded() {
        guard settings.showSecondClockOverlay else {
            backdropCapture.stop()
            return
        }
        let blurRadius = (30 * settings.overlaySize.scale).clamped(to: 16...50)
        backdropCapture.start(window: window, blurRadius: blurRadius)
    }
}
