import AppKit
import SwiftUI
import Combine

/// Owns an optional second `NSStatusItem` showing a live clock for a
/// user-chosen timezone. Created/destroyed as `settings.showSecondClock`
/// toggles — unlike the primary status item, this one is view-only (no
/// popover/menu of its own; Settings and Quit are already reachable from
/// the primary clock's right-click menu).
final class SecondClockStatusItemController {
    private var statusItem: NSStatusItem?
    private let timeProvider: TimeProvider
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(timeProvider: TimeProvider, settings: AppSettings) {
        self.timeProvider = timeProvider
        self.settings = settings

        setVisible(settings.showSecondClock)
        settings.$showSecondClock
            .dropFirst()
            .sink { [weak self] visible in
                self?.setVisible(visible)
            }
            .store(in: &cancellables)
        settings.$timeFormat
            .dropFirst()
            .sink { [weak self] _ in self?.refreshSize() }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        guard visible else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshSize()
    }

    private func refreshSize() {
        guard let item = statusItem else { return }
        let itemSize = MenuBarClockView.itemSize(timeFormat: settings.timeFormat)
        item.length = itemSize.width

        let hosting = NSHostingView(rootView: SecondClockMenuBarView(timeProvider: timeProvider, settings: settings))
        hosting.frame = NSRect(x: 0, y: 0, width: itemSize.width, height: itemSize.height)
        item.button?.subviews.forEach { $0.removeFromSuperview() }
        item.button?.addSubview(hosting)
    }
}
