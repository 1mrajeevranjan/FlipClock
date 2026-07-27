import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let timeProvider = TimeProvider()
    let settings = AppSettings()
    let reminderStore = ReminderStore()

    private var statusItemController: StatusItemController?
    private var secondClockStatusItemController: SecondClockStatusItemController?
    private var overlayWindowController: OverlayWindowController?
    private var secondClockOverlayWindowController: SecondClockOverlayWindowController?
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetFont.registerAll()
        statusItemController = StatusItemController(timeProvider: timeProvider, settings: settings, reminderStore: reminderStore) { [weak self] in
            self?.settingsWindowController.show()
        }
        secondClockStatusItemController = SecondClockStatusItemController(timeProvider: timeProvider, settings: settings)
        overlayWindowController = OverlayWindowController(timeProvider: timeProvider, settings: settings, reminderStore: reminderStore)
        secondClockOverlayWindowController = SecondClockOverlayWindowController(timeProvider: timeProvider, settings: settings)
    }
}
