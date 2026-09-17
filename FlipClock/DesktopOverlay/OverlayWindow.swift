import AppKit
import CoreGraphics

/// Borderless panel pinned at desktop level — above desktop icons, below
/// normal app windows, visible on every Space, draggable by its background.
final class OverlayWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // Overridden to `true`/`false` on every layout pass by
        // `OverlayWindowController.applySize` — see that call site for why
        // the native shadow stays off outside full-screen too.
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
    }

    /// Drives the drag directly rather than leaving it to
    /// `isMovableByWindowBackground`, which does not work for this window.
    ///
    /// Confirmed by logging: the panel receives the whole gesture —
    /// `leftMouseDown`, three `leftMouseDragged`, `leftMouseUp` — with
    /// `isMovableByWindowBackground == true` the entire time, and its frame
    /// origin never changes. A borderless, non-activating panel parked at
    /// desktop level simply doesn't get AppKit's built-in background drag, so
    /// the flag alone is not enough no matter which view answers `true` to
    /// `mouseDownCanMoveWindow`.
    ///
    /// `performDrag` runs its own tracking loop until mouseUp and no-ops on a
    /// click that never moves, so this costs nothing when the user just
    /// clicks. `isMovableByWindowBackground` is still the switch that says
    /// whether dragging is allowed at all — `OverlayWindowController` turns it
    /// off for full-screen and float-across-screen modes, which own the
    /// window's position themselves.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isMovableByWindowBackground {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
