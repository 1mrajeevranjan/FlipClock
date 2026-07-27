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
            // Matches `SettingsTab.general`'s real target size (470×184) —
            // starting from a different placeholder size caused a visible
            // resize animation on first launch, before the user had even
            // touched a tab.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 470, height: 184),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "General"
            // AppKit only centers a titled window's title against a unified
            // NSToolbar's layout guide — a plain `.fullSizeContentView`
            // window with no toolbar (this one) left-aligns the title text
            // right after the traffic lights instead. `SettingsView` draws
            // its own centered title into that same reserved band via
            // `.ignoresSafeArea`, so the native one stays hidden here.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(onChangeWindow: { [weak window] title, size in
                    guard let window else { return }
                    window.title = title
                    Self.position(window: window, contentSize: size)
                })
                .environmentObject(settings)
            )
            self.window = window
            Self.position(window: window, contentSize: .init(width: 470, height: 184))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Resizes the window to fit `contentSize`, top-right anchored.
    ///
    /// The resize is deliberately **not** animated. An animated window
    /// frame was the root cause of the tab pill appearing to "bounce" on
    /// General↔Appearance while sliding cleanly on every other tab pair —
    /// a bug that survived several rounds of fixes aimed at the SwiftUI
    /// animation itself, because the SwiftUI side was never what was wrong.
    ///
    /// What the measurements showed: tracking the pill's full bounding box
    /// per frame at 60fps (x, y, width *and* height — tracking x alone
    /// looked perfectly clean and completely masked this) caught its
    /// *vertical* position dipping ~39pt and easing back over the
    /// transition — y = 64 → 103 → 97 → 93 → 88 → 74 → 70 → 66 → 64 —
    /// against a flat y = 64 on every frame of Appearance→Desktop Clock.
    /// That vertical arc is what reads as a bounce.
    ///
    /// The cause is a layout lag inherent to animating an `NSWindow` that
    /// hosts SwiftUI: `NSHostingView` is laid out in AppKit's bottom-left
    /// origin space, so while `animator().setFrame` grows the window with
    /// its top edge pinned, it is the *bottom* edge that is actually
    /// moving. Until SwiftUI re-lays-out at each intermediate height,
    /// top-aligned content is placed relative to a stale height measured up
    /// from that moving bottom edge — so it renders low and creeps back up
    /// as layout catches up. The larger the height delta the larger the
    /// dip, and General↔Appearance is the largest delta of any pair (General
    /// being by far the shortest tab), which is exactly why that one pair
    /// looked different from the rest.
    ///
    /// Pinning the hosting view to the window's top edge via a container
    /// and `.minYMargin` autoresizing was tried and made it strictly worse
    /// (dip grew to ~74pt, and the pill was clipped mid-transition):
    /// `NSHostingView` installs its own Auto Layout constraints and does
    /// not honour an `autoresizingMask`.
    ///
    /// Removing the window animation removes the stale-layout window
    /// altogether — there are no intermediate frames to lag behind, so the
    /// header cannot move, and the pill's own 0.2s SwiftUI slide (pure
    /// horizontal arithmetic — see `SettingsView.pillOffset`) is the only
    /// motion left. Every tab pair now animates identically, which is the
    /// requirement.
    private static func position(window: NSWindow, contentSize: CGSize) {
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize))
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let screenFrame else {
            window.setFrame(frame, display: true, animate: false)
            return
        }

        var origin = NSPoint(
            x: screenFrame.maxX - frame.width - 12,
            y: screenFrame.maxY - frame.height - 12
        )
        origin.x = max(origin.x, screenFrame.minX + 12)
        origin.y = max(origin.y, screenFrame.minY + 12)

        window.setFrame(frame.offsetBy(dx: origin.x, dy: origin.y), display: true, animate: false)
    }
}
