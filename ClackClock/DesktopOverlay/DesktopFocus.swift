import AppKit

/// Whether the user is "on the desktop" — the state in which macOS's own
/// desktop widgets drop their dimmed look and turn vivid when "Dim widgets on
/// desktop" is set to Automatic. There's no public API for it, so it's
/// inferred the way it looks from outside: Finder is frontmost (clicking the
/// wallpaper activates Finder) and no window — any app's — is still mostly on
/// screen. Compared against the system widgets side by side, that's when they
/// turn vivid: clicking the wallpaper slides every window off to the screen
/// edges, leaving only slivers, which don't count. Finder merely being in
/// front while other windows stay put leaves them dimmed.
enum DesktopFocus {
    struct WindowInfo {
        let layer: Int
        let bounds: CGRect
        let alpha: Double
    }

    static let finderBundleID = "com.apple.finder"

    /// A window counts as "in front of the desktop" only when most of it is
    /// actually on a screen.
    static let onScreenFraction: CGFloat = 0.5
    /// Ignores the invisible/tiny helper windows apps park at layer 0.
    static let minimumSide: CGFloat = 80

    static func isFocused(frontmostBundleID: String?, windows: [WindowInfo], screens: [CGRect]) -> Bool {
        guard frontmostBundleID == finderBundleID else { return false }
        return !windows.contains { window in
            window.layer == 0
                && window.alpha > 0
                && window.bounds.width >= minimumSide
                && window.bounds.height >= minimumSide
                && visibleFraction(of: window.bounds, on: screens) > onScreenFraction
        }
    }

    static func visibleFraction(of rect: CGRect, on screens: [CGRect]) -> CGFloat {
        let area = rect.width * rect.height
        guard area > 0 else { return 0 }
        let visible = screens.reduce(CGFloat(0)) { total, screen in
            let overlap = rect.intersection(screen)
            return overlap.isNull ? total : total + overlap.width * overlap.height
        }
        return visible / area
    }

    /// What a click at `point` (top-left-origin global coordinates) means for
    /// desktop focus: `true` for the wallpaper or desktop icons, `false` for
    /// an app window, `nil` for anything that doesn't change focus (menu bar,
    /// Dock, widgets, floating panels).
    ///
    /// This is what lets the widget change look the moment the user clicks,
    /// like the system's own widgets do, instead of waiting for the windows
    /// to finish sliding aside before `isFocused` can see it.
    ///
    /// Layers at and above the Dock's are skipped, not hit-tested: the Dock
    /// and several menu-bar/notch utilities park fully transparent
    /// *full-screen* windows up there that clicks pass straight through.
    /// Taking the front-most window under the pointer landed on the Dock for
    /// every click on the screen, so this answered "no change" every time and
    /// the instant path never fired. The real menu bar and Dock strip are
    /// excluded by position instead — they're outside `visibleFrames`.
    static func clickTarget(at point: CGPoint, windows: [WindowInfo], visibleFrames: [CGRect]) -> Bool? {
        guard visibleFrames.contains(where: { $0.contains(point) }) else { return nil }
        let overlayFloor = Int(CGWindowLevelForKey(.dockWindow))
        let desktopTop = Int(CGWindowLevelForKey(.desktopIconWindow))
        guard let hit = windows.first(where: {
            $0.layer < overlayFloor && $0.alpha > 0 && $0.bounds.contains(point)
        }) else { return true }
        if hit.layer <= desktopTop { return true }
        if hit.layer == 0 { return false }
        return nil
    }

    /// Windows under the pointer right now, front to back, desktop included.
    static func clickTargetNow() -> Bool? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let location = NSEvent.mouseLocation
        let point = CGPoint(x: location.x, y: primaryHeight - location.y)
        let visibleFrames = NSScreen.screens.map { screen in
            CGRect(x: screen.visibleFrame.minX, y: primaryHeight - screen.visibleFrame.maxY, width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        }
        return clickTarget(at: point, windows: windowInfos(options: [.optionOnScreenOnly]), visibleFrames: visibleFrames)
    }

    private static func windowInfos(options: CGWindowListOption) -> [WindowInfo] {
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { info -> WindowInfo? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(layer: layer, bounds: bounds, alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    /// Live read of the current state.
    static func current() -> Bool {
        let workspace = NSWorkspace.shared
        let frontmost = workspace.frontmostApplication
        guard frontmost?.bundleIdentifier == finderBundleID else { return false }
        let windows = windowInfos(options: [.optionOnScreenOnly, .excludeDesktopElements])
        // CG window bounds are top-left-origin global coordinates; converting
        // every screen the same way keeps the overlap maths in one space.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        }
        return isFocused(frontmostBundleID: frontmost?.bundleIdentifier, windows: windows, screens: screens)
    }
}
