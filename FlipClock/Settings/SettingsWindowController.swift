import AppKit
import SwiftUI

/// Owns a self-managed Settings window instead of relying on SwiftUI's
/// `Settings` scene / `showSettingsWindow:` selector trick — that path is
/// unreliable for `LSUIElement` (accessory, no Dock icon) apps like this
/// one, since there's no regular window ever establishing the app's
/// normal responder chain for AppKit to find the action on. A window we
/// create and show ourselves always works regardless of activation policy.
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 220),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "General"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(onChangeWindow: { [weak window] title, size in
                    guard let window else { return }
                    window.title = title
                    Self.position(window: window, contentSize: size, animated: true)
                })
                .environmentObject(settings)
            )
            self.window = window
            Self.position(window: window, contentSize: .init(width: 430, height: 220), animated: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func position(window: NSWindow, contentSize: CGSize, animated: Bool) {
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize))
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let screenFrame else {
            window.setFrame(frame, display: true, animate: animated)
            return
        }

        var origin = NSPoint(
            x: screenFrame.maxX - frame.width - 12,
            y: screenFrame.maxY - frame.height - 12
        )
        origin.x = max(origin.x, screenFrame.minX + 12)
        origin.y = max(origin.y, screenFrame.minY + 12)

        window.setFrame(frame.offsetBy(dx: origin.x, dy: origin.y), display: true, animate: animated)
    }
}
