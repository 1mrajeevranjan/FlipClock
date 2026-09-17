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
            let hosting = NSHostingController(
                rootView: SettingsView(onChangeWindow: { [weak window] title, size in
                    guard let window else { return }
                    window.title = title
                    Self.resize(window: window, contentSize: size)
                })
                .environmentObject(settings)
            )
            window.contentViewController = hosting
            self.window = window
            Self.resize(window: window, contentSize: .init(width: 470, height: 184))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Resizes the window to fit `contentSize`, keeping its **top-left corner
    /// where it already is** so switching tabs grows and shrinks the window
    /// downward in place.
    ///
    /// This used to re-derive the origin from the screen on every call and
    /// pin the window to the top-right corner, which meant a tab switch
    /// yanked the window back to the corner from wherever the user had
    /// dragged it — and left it jammed against the screen edge the rest of
    /// the time. Placement now happens exactly once, in `show()`.
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
    private static func resize(window: NSWindow, contentSize: CGSize) {
        // `contentSize` is used as the *frame* size, not run through
        // `frameRect(forContentRect:)`. This window is `.fullSizeContentView`,
        // so its content view already spans the whole frame including the
        // titlebar band — and `SettingsView` lays its own title out inside
        // that band. Converting would have added another titlebar's height on
        // top, which is the ~28pt of dead space that sat under the last
        // control on every tab.
        let sized = CGRect(origin: .zero, size: contentSize)
        // Cocoa origins are bottom-left, so holding the *top* edge still means
        // moving the origin down by however much the height grew.
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        var frame = NSRect(
            x: topLeft.x,
            y: topLeft.y - sized.height,
            width: sized.width,
            height: sized.height
        )

        // Only nudge back on-screen if growing pushed it off — never recentre,
        // or the window would creep away from where the user put it.
        if let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.y = max(frame.origin.y, visible.minY)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        }

        window.setFrame(frame, display: true, animate: false)
    }
}
