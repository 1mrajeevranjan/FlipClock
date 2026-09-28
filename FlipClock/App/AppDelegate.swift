import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let timeProvider = TimeProvider()
    let settings = AppSettings()
    let reminderStore = ReminderStore()
    let timerModel = CountdownTimer()
    let stopwatch = Stopwatch()

    private var statusItemController: StatusItemController?
    private var overlayWindowController: OverlayWindowController?
    private var worldClocksCoordinator: WorldClocksCoordinator?
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetFont.registerAll()
        statusItemController = StatusItemController(timeProvider: timeProvider, settings: settings, reminderStore: reminderStore, timerModel: timerModel, stopwatch: stopwatch) { [weak self] in
            self?.settingsWindowController.show()
        }
        overlayWindowController = OverlayWindowController(timeProvider: timeProvider, settings: settings, reminderStore: reminderStore) { [weak self] in
            self?.settingsWindowController.show()
        }
        worldClocksCoordinator = WorldClocksCoordinator(timeProvider: timeProvider, settings: settings) { [weak self] in
            self?.settingsWindowController.show()
        }
    }
}
