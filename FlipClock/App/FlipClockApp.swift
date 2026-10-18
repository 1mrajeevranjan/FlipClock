import SwiftUI

@main
struct FlipClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(reminderNotifications: appDelegate.reminderNotifications)
                .environmentObject(appDelegate.settings)
        }
    }
}
