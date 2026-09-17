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
    /// The loop is hand-rolled rather than left to `performDrag(with:)` for
    /// one reason: `onDragStep`. `performDrag` runs its own modal event loop
    /// and only coalesced `NSWindow.didMoveNotification`s come out of it, so
    /// the widget's glass — which re-crops the desktop backdrop on each move —
    /// updated a couple of times across a whole gesture instead of every
    /// frame, and visibly carried the old location's wallpaper around
    /// mid-drag. Tracking the events here means the backdrop is recomputed in
    /// lockstep with the window, once per `leftMouseDragged`.
    ///
    /// `isMovableByWindowBackground` is still the switch that says whether
    /// dragging is allowed at all — `OverlayWindowController` turns it off for
    /// full-screen and float-across-screen modes, which own the window's
    /// position themselves.
    var onDragStep: (() -> Void)?
    /// Called once the gesture ends, so the backdrop can be re-captured for
    /// the new location — the per-step crop keeps the position right, but the
    /// pixels are still as old as the last refresh.
    var onDragEnd: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isMovableByWindowBackground {
            trackDrag(from: event)
            return
        }
        super.sendEvent(event)
    }

    private func trackDrag(from mouseDown: NSEvent) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin

        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            guard event.type == .leftMouseDragged else { break }
            let current = NSEvent.mouseLocation
            setFrameOrigin(
                NSPoint(
                    x: startOrigin.x + (current.x - startMouse.x),
                    y: startOrigin.y + (current.y - startMouse.y)
                )
            )
            onDragStep?()
        }
        onDragEnd?()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
