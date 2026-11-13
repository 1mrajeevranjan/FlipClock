import AppKit
import SwiftUI
import Combine

/// One world clock's desktop widget — the same borderless desktop-level
/// `OverlayWindow` and glass treatment as the main clock's
/// `OverlayWindowController`, pinned to the clock's time zone and labelled
/// with its name. Deliberately skips the main widget's float-across-screen and
/// fill-screen modes: these are companion widgets, not the main clock.
///
/// Lives exactly as long as the clock is set to show as a widget —
/// `WorldClocksCoordinator` creates and closes these — so a switched-off
/// clock costs no window, no capture and no timers at all.
final class WorldClockOverlayWindowController {
    private let window: OverlayWindow
    private let clockID: WorldClock.ID
    private let settings: AppSettings
    private let backdropCapture = DesktopBackdropCapture()
    private let visibility: WindowVisibility
    private var cancellables = Set<AnyCancellable>()

    /// `slot` staggers first-launch placement so new widgets don't open
    /// stacked exactly on top of each other.
    init(clockID: WorldClock.ID, slot: Int, timeProvider: TimeProvider, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.clockID = clockID
        self.settings = settings
        window = OverlayWindow()

        visibility = WindowVisibility(window: window, timeProvider: timeProvider)
        let hostingController = NSHostingController(
            rootView: WorldClockOverlayContentView(clockID: clockID, timeProvider: timeProvider, settings: settings, backdropCapture: backdropCapture, visibility: visibility)
        )
        window.contentViewController = hostingController
        window.installContextMenu(openSettings: openSettings) { [weak settings] in
            guard let settings, let index = settings.worldClocks.firstIndex(where: { $0.id == clockID }) else { return }
            settings.worldClocks[index].showsAsWidget = false
        }

        applySize(slot: slot)
        window.setFrameAutosaveName(Self.frameAutosaveName(for: clockID))

        window.orderFront(nil)
        startBackdropCapture()
        settings.startWatchingSystemWidgetAppearance()

        // Size, format and name all change the window's size; the time zone
        // changes the name's width when there's no custom label.
        settings.$worldClocks
            .receive(on: DispatchQueue.main)
            .compactMap { clocks in clocks.first { $0.id == clockID } }
            .map { LayoutKey(clock: $0) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.applySize(slot: nil)
                self?.startBackdropCapture()
            }
            .store(in: &cancellables)

        settings.$showDateOnOverlay
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySize(slot: nil) }
            .store(in: &cancellables)
    }

    static func frameAutosaveName(for id: WorldClock.ID) -> String {
        "WorldClockFrame-\(id.uuidString)"
    }

    /// The parts of a clock that affect the window's size.
    private struct LayoutKey: Equatable {
        let label: String
        let size: OverlaySize
        let format: TimeFormat

        init(clock: WorldClock) {
            label = WorldClockOverlayContentView.flapLabel(for: clock)
            size = clock.widgetSize
            format = clock.timeFormat
        }
    }

    private var clock: WorldClock? { settings.worldClocks.first { $0.id == clockID } }

    /// `slot` non-nil = first placement (top-right, staggered); nil = resize in
    /// place, pinned at the current top-left corner.
    private func applySize(slot: Int?) {
        guard let clock else { return }
        window.isMovableByWindowBackground = true
        window.hasShadow = false

        let scale = clock.widgetSize.scale
        let contentSize = WorldClockOverlayContentView.windowSize(
            scale: scale,
            showDate: settings.showDateOnOverlay,
            showMeridiem: clock.timeFormat == .twelveHour,
            timezoneLabel: WorldClockOverlayContentView.flapLabel(for: clock)
        )
        let previousTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(contentSize)

        if let slot, let screen = NSScreen.main {
            let margin: CGFloat = 40
            let stagger: CGFloat = 32
            let origin = NSPoint(
                x: screen.visibleFrame.maxX - contentSize.width - margin - 260 - CGFloat(slot) * stagger,
                y: screen.visibleFrame.maxY - contentSize.height - margin - CGFloat(slot) * stagger
            )
            window.setFrameOrigin(origin)
        } else {
            window.setFrameOrigin(NSPoint(x: previousTopLeft.x, y: previousTopLeft.y - contentSize.height))
        }
        maskContentView(cornerRadius: WidgetGlassBackground.cornerRadius(scale: scale))
    }

    private func maskContentView(cornerRadius: CGFloat) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
    }

    func close() {
        cancellables.removeAll()
        window.onDragStep = nil
        window.onDragEnd = nil
        backdropCapture.stop()
        window.orderOut(nil)
        // Deferred: this runs from the `worldClocks` change that switched the
        // widget off, before the new value is stored, so reading
        // `anyWidgetVisible` synchronously would still count this widget.
        DispatchQueue.main.async { [settings] in
            if !settings.anyWidgetVisible { settings.stopWatchingSystemWidgetAppearance() }
        }
    }

    private func startBackdropCapture() {
        guard let clock else { return }
        let scale = clock.widgetSize.scale
        // Tuned against real macOS widget glass by measuring high-frequency
        // detail energy in screenshots: at 30pt the backdrop washed out to a
        // flat colour field (energy ~0.34) while Notification Center's own
        // widgets sit around 1.0-1.7, still showing the wallpaper's large-scale
        // structure through the frost. ~16pt lands in that range.
        let blurRadius = (4 * scale).clamped(to: 2.5...8)
        backdropCapture.start(window: window, blurRadius: blurRadius, dimmedBlurRadius: WidgetGlassBackground.dimmedBlur(scale: scale))
        // Re-crop the backdrop on every frame of a user drag, so the glass
        // tracks the desktop instead of dragging the old spot's wallpaper.
        window.onDragStep = { [weak self, weak window] in
            guard let self, let window else { return }
            // Event tracking is main-thread by definition; a hop would put the
            // backdrop a frame behind the window it belongs to.
            MainActor.assumeIsolated { self.backdropCapture.publishCrop(for: window) }
        }
        window.onDragEnd = { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.backdropCapture.refreshNow() }
        }
    }
}
