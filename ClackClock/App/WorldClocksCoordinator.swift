import Foundation
import Combine

/// Keeps one menu-bar item and/or one desktop widget alive per world clock,
/// matching `AppSettings.worldClocks`: creating them as clocks are added or
/// switched on, removing them as clocks are removed or switched off.
final class WorldClocksCoordinator {
    private var menuBarItems: [WorldClock.ID: WorldClockStatusItemController] = [:]
    private var widgets: [WorldClock.ID: WorldClockOverlayWindowController] = [:]
    private var cancellable: AnyCancellable?

    init(timeProvider: TimeProvider, settings: AppSettings, openSettings: @escaping () -> Void) {
        // `$worldClocks` hands over the new value before it's stored; the
        // controllers created here read `settings.worldClocks` themselves, so
        // reconcile on the next turn, once it has been.
        cancellable = settings.$worldClocks
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak settings] clocks in
                guard let self, let settings else { return }
                self.reconcile(clocks, timeProvider: timeProvider, settings: settings, openSettings: openSettings)
            }
    }

    private func reconcile(_ clocks: [WorldClock], timeProvider: TimeProvider, settings: AppSettings, openSettings: @escaping () -> Void) {
        let menuBarIDs = Set(clocks.filter(\.showsInMenuBar).map(\.id))
        for (id, item) in menuBarItems where !menuBarIDs.contains(id) {
            item.remove()
            menuBarItems[id] = nil
        }
        for clock in clocks where clock.showsInMenuBar && menuBarItems[clock.id] == nil {
            menuBarItems[clock.id] = WorldClockStatusItemController(clockID: clock.id, timeProvider: timeProvider, settings: settings)
        }

        let widgetIDs = Set(clocks.filter(\.showsAsWidget).map(\.id))
        for (id, widget) in widgets where !widgetIDs.contains(id) {
            widget.close()
            widgets[id] = nil
        }
        for (slot, clock) in clocks.enumerated() where clock.showsAsWidget && widgets[clock.id] == nil {
            widgets[clock.id] = WorldClockOverlayWindowController(
                clockID: clock.id,
                slot: slot,
                timeProvider: timeProvider,
                settings: settings,
                openSettings: openSettings
            )
        }
    }
}
