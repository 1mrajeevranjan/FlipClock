import AppKit
import SwiftUI

/// Accessory apps have no reliable Settings responder chain, so this window is owned explicitly.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let reminderNotifications: ReminderNotifications

    init(settings: AppSettings, reminderNotifications: ReminderNotifications) {
        self.settings = settings
        self.reminderNotifications = reminderNotifications
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsView.minimumWidth, height: 320),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .windowBackgroundColor
            window.contentMinSize = NSSize(width: SettingsView.minimumWidth, height: 220)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("FlipClockSettings")
            window.contentViewController = NSHostingController(
                rootView: SettingsView(reminderNotifications: reminderNotifications, onContentHeightChange: { [weak window] height in
                    guard let window, height > 0 else { return }
                    let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
                    let content = NSRect(x: 0, y: 0, width: window.frame.width, height: max(220, height.rounded(.up)))
                    let frameHeight = min(visible.height, window.frameRect(forContentRect: content).height)
                    guard abs(window.frame.height - frameHeight) > 1 else { return }
                    var frame = window.frame
                    frame.origin.y = max(visible.minY, frame.maxY - frameHeight)
                    frame.size.height = frameHeight
                    // No animated NSWindow resize: hosted SwiftUI content lags intermediate frames.
                    window.setFrame(frame, display: true, animate: false)
                }).environmentObject(settings)
            )
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
