import AppKit
import SwiftUI
import Combine

/// One world clock's `NSStatusItem`. View-only (no popover or menu of its
/// own — Settings and Quit live on the main clock's item). Lives exactly as
/// long as the clock is set to show in the menu bar; `WorldClocksCoordinator`
/// creates and removes these.
final class WorldClockStatusItemController {
    private let statusItem: NSStatusItem
    private let clockID: WorldClock.ID
    private let timeProvider: TimeProvider
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(clockID: WorldClock.ID, timeProvider: TimeProvider, settings: AppSettings) {
        self.clockID = clockID
        self.timeProvider = timeProvider
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers where the user Cmd-dragged it in the menu bar. (New items
        // always start at the far left of the status area; on a full, notched
        // menu bar that can be behind the notch or a menu-bar hider until the
        // user drags it into view once.)
        statusItem.autosaveName = "WorldClock-\(clockID.uuidString)"

        settings.$worldClocks
            .receive(on: DispatchQueue.main)
            .compactMap { clocks in clocks.first { $0.id == clockID } }
            .removeDuplicates()
            .sink { [weak self] clock in self?.render(clock) }
            .store(in: &cancellables)
    }

    private func render(_ clock: WorldClock) {
        let size = WorldClockMenuBarView.itemSize(label: clock.menuBarLabel, timeFormat: clock.timeFormat)
        statusItem.length = size.width

        let hosting = NSHostingView(rootView: WorldClockMenuBarView(timeProvider: timeProvider, clock: clock, settings: settings))
        hosting.frame = NSRect(origin: .zero, size: size)
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.addSubview(hosting)
        statusItem.button?.toolTip = "\(clock.displayName) — \(clock.timezoneID) (\(WorldClock.offsetLabel(for: clock.timeZone)))"
    }

    func remove() {
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
