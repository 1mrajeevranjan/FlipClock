import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let timeProvider = TimeProvider()
    let settings = AppSettings()

    private var statusItemController: StatusItemController?
    private var secondClockStatusItemController: SecondClockStatusItemController?
    private var overlayWindowController: OverlayWindowController?
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(timeProvider: timeProvider, settings: settings) { [weak self] in
            self?.settingsWindowController.show()
        }
        secondClockStatusItemController = SecondClockStatusItemController(timeProvider: timeProvider, settings: settings)
        overlayWindowController = OverlayWindowController(timeProvider: timeProvider, settings: settings)
    }
}
