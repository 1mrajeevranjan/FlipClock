import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem: hosts the live-animating compact clock, routes
/// left-click to a popover (full clock) and right-click to a menu
/// (Settings / Quit).
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let timeProvider: TimeProvider
    private let settings: AppSettings
    private let reminderStore: ReminderStore
    private let timerModel: CountdownTimer
    private let stopwatch: Stopwatch
    private let popoverPresentation: PopoverPresentation
    private let onOpenSettings: () -> Void
    private var hosting: NSHostingView<MenuBarClockView>?
    private var cancellables = Set<AnyCancellable>()

    /// Reminder pulses change emphasis without overriding the chosen theme.
    private var reminderPulseDimmed = false {
        didSet { updateHostedRootView() }
    }
    private var pulseTimer: Timer?

    init(timeProvider: TimeProvider, settings: AppSettings, reminderStore: ReminderStore, timerModel: CountdownTimer, stopwatch: Stopwatch, onOpenSettings: @escaping () -> Void) {
        self.timeProvider = timeProvider
        self.settings = settings
        self.reminderStore = reminderStore
        self.timerModel = timerModel
        self.stopwatch = stopwatch
        popoverPresentation = PopoverPresentation(timeProvider: timeProvider, timerModel: timerModel, stopwatch: stopwatch)
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        applyItemSize(timeFormat: settings.timeFormat)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = VibrantHostingController(
            rootView: PopoverClockView(timeProvider: timeProvider, settings: settings, reminderStore: reminderStore, timerModel: timerModel, stopwatch: stopwatch, presentation: popoverPresentation),
            settings: settings
        )

        // Switching 12h/24h changes whether the AM/PM card renders, which
        // changes the item's ideal width — reapply so the status item
        // never ends up with leftover empty space or clipped content.
        settings.$timeFormat
            .dropFirst()
            .sink { [weak self] format in self?.applyItemSize(timeFormat: format) }
            .store(in: &cancellables)

        settings.$theme
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHostedRootView() }
            .store(in: &cancellables)

        reminderStore.$reminders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePulseState() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePulseState() }
            .store(in: &cancellables)
        updatePulseState()
    }

    private func applyItemSize(timeFormat: TimeFormat) {
        let itemSize = MenuBarClockView.itemSize(timeFormat: timeFormat)
        statusItem.length = itemSize.width

        let hosting = NSHostingView(rootView: MenuBarClockView(timeProvider: timeProvider, settings: settings, reminderPulseDimmed: reminderPulseDimmed))
        hosting.frame = NSRect(x: 0, y: 0, width: itemSize.width, height: itemSize.height)
        self.hosting = hosting

        if let button = statusItem.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(hosting)
        }
    }

    /// The actual fix for the pulse never visually repainting: an
    /// `NSStatusItem`'s button subview doesn't redraw on its own just
    /// because a hosted SwiftUI view's `rootView` changed — confirmed the
    /// hard way (state changes verified firing correctly via logging,
    /// zero visible change) with both a plain `rootView` reassignment and
    /// a `TimelineView`-only approach. `NSStatusBarButton` composites its
    /// content into the menu bar through a separate (SkyLight) pipeline
    /// that isn't part of a normal window's live-updating render loop, so
    /// it needs to be told explicitly, on the *button* itself (not just
    /// the hosted subview), that its content changed.
    private func updateHostedRootView() {
        hosting?.rootView = MenuBarClockView(timeProvider: timeProvider, settings: settings, reminderPulseDimmed: reminderPulseDimmed)
        statusItem.button?.needsDisplay = true
    }

    private func updatePulseState() {
        let isDue = !reminderStore.dueTodayUnacknowledged.isEmpty
        guard isDue else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            reminderPulseDimmed = false
            return
        }
        guard pulseTimer == nil else { return }
        reminderPulseDimmed = true
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.reminderStore.dueTodayUnacknowledged.isEmpty {
                self.updatePulseState()
            } else {
                self.reminderPulseDimmed.toggle()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Leave popover.appearance nil (system default) so the frame's
            // arrow-tip vibrancy resolves the same way our content's own
            // NSVisualEffectView does — forcing a concrete .aqua/.darkAqua
            // here made the frame and the nested effect view compute
            // vibrancy along different paths, which was *why* the body
            // looked muted/flat next to the tip despite using the same
            // material name. Light/Dark/System is instead applied
            // directly to the effect view itself (see
            // VibrantHostingController), which is the correct place to
            // control it without touching the frame's own resolution.
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        popoverPresentation.setPresented(true, timeProvider: timeProvider)
    }

    func popoverDidClose(_ notification: Notification) {
        popoverPresentation.setPresented(false, timeProvider: timeProvider)
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        // No manual icon here: macOS auto-adds a gear to any "Settings…"
        // item with the standard ⌘, key equivalent — setting our own
        // attributedTitle on top of that doubled up the gear glyph.
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self

        let moreItem = menu.addItem(withTitle: "More", action: nil, keyEquivalent: "")
        moreItem.attributedTitle = Self.iconTitle("More", symbol: "ellipsis.circle")
        moreItem.submenu = Self.makeMoreMenu(target: self)

        menu.addItem(.separator())

        let quitItem = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.attributedTitle = Self.iconTitle("Quit", symbol: "power")
        // popUp(positioning:at:in:) shows a one-off context menu without
        // assigning statusItem.menu, which would otherwise permanently
        // override left-click (popover) behavior.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    static func makeMoreMenu(target: NSObject) -> NSMenu {
        let submenu = NSMenu()
        func item(_ title: String, symbol: String, action: Selector? = nil) {
            let menuItem = submenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            menuItem.target = target
            if action == nil {
                menuItem.isEnabled = false
                menuItem.toolTip = "No destination has been configured for this command."
            }
            if let attributed = Self.iconTitle(title, symbol: symbol) {
                menuItem.attributedTitle = attributed
            }
        }
        item("About", symbol: "info.circle", action: #selector(showAbout))
        item("Support & Feedback", symbol: "bubble.left")
        submenu.addItem(.separator())
        item("Tips", symbol: "lightbulb", action: #selector(showTips))
        item("FAQ", symbol: "questionmark.circle", action: #selector(showFAQ))
        item("Website", symbol: "globe")
        submenu.addItem(.separator())
        item("Rate App", symbol: "star")
        item("Share App", symbol: "square.and.arrow.up")
        item("More Apps by Me", symbol: "square.stack.3d.up")
        return submenu
    }

    /// Assigning a rasterized SF Symbol to `NSMenuItem.image` renders as
    /// blank on this toolchain (a macOS 27 SDK beta) — confirmed by dumping
    /// the actual rasterized bitmap to a PNG and inspecting it directly: the
    /// pixel data is a perfectly valid, correctly drawn icon, and the
    /// `NSMenuItem` it's assigned to is enabled, yet nothing paints in the
    /// menu. That's a dead end in AppKit's icon-slot rendering, not
    /// something fixable from here. `NSMenuItem.title`, by contrast,
    /// renders correctly (proven by every label in this same menu already
    /// being visible), so the icon is instead embedded as an
    /// `NSTextAttachment` inside `attributedTitle`, riding the text-drawing
    /// path instead of the broken image-slot path.
    private static func iconTitle(_ title: String, symbol: String, pointSize: CGFloat = 13) -> NSAttributedString? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = icon
        // Nudge down from the text baseline so the glyph optically centers
        // against the menu's label instead of sitting high against its cap height.
        attachment.bounds = NSRect(x: 0, y: -(icon.size.height - 13) / 2 - 2, width: icon.size.width, height: icon.size.height)

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "  " + title, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        return result
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showTips() {
        showHelp(title: "FlipClock Tips", text: """
        Click the menu bar clock to open Calendar, Timer, and Stopwatch. Right-click it for Settings and Quit.

        In the calendar, click the month and year to browse months, then years. Click empty space to go back one level. Double-click a day, or select it and press ⌘N, to add a reminder.

        Scroll a timer column, or click it and use ↑ / ↓, to adjust the duration. Space pauses or resumes an active timer or stopwatch; ⌘R resets it. Use ⌘1–⌘3 to switch tools.

        Drag a desktop widget to move it. Right-click a widget to open Settings or hide it.
        """)
    }

    @objc private func showFAQ() {
        showHelp(title: "FlipClock FAQ", text: """
        Where are Settings? Right-click the menu bar clock and choose Settings…

        Why is a widget hidden? Desktop widgets sit beneath other app windows. Show the desktop to reveal them.

        Why is the glass softer? Stronger wallpaper diffusion needs Screen Recording permission. The clock still works with system vibrancy when permission is unavailable.

        How do reminder sounds work? Choose a native sound in General settings and allow FlipClock alerts and sounds in System Settings › Notifications. Dismiss acknowledges the reminder and clears it from active views. macOS controls playback of its one-shot notification sound.

        Do timers continue when the popover closes? Yes. Reopening immediately shows the current time without keeping hidden display animations running.
        """)
    }

    private func showHelp(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
