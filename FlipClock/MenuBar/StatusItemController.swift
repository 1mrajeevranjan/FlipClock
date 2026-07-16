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
    private let onOpenSettings: () -> Void
    private var hosting: NSHostingView<MenuBarClockView>?
    private var cancellables = Set<AnyCancellable>()

    init(timeProvider: TimeProvider, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.timeProvider = timeProvider
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        applyItemSize()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = VibrantHostingController(
            rootView: PopoverClockView(timeProvider: timeProvider, settings: settings),
            settings: settings
        )

        // Switching 12h/24h changes whether the AM/PM card renders, which
        // changes the item's ideal width — reapply so the status item
        // never ends up with leftover empty space or clipped content.
        settings.$timeFormat
            .dropFirst()
            .sink { [weak self] _ in self?.applyItemSize() }
            .store(in: &cancellables)
    }

    private func applyItemSize() {
        let itemSize = MenuBarClockView.itemSize(timeFormat: settings.timeFormat)
        statusItem.length = itemSize.width

        let hosting = NSHostingView(rootView: MenuBarClockView(timeProvider: timeProvider, settings: settings))
        hosting.frame = NSRect(x: 0, y: 0, width: itemSize.width, height: itemSize.height)
        self.hosting = hosting

        if let button = statusItem.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(hosting)
        }
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
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
}
