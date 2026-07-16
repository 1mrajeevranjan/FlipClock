import Foundation
import Combine
import ServiceManagement
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// nil lets SwiftUI/AppKit resolve to the current system appearance —
    /// `.preferredColorScheme(nil)` at each root view is what makes
    /// "System" track live appearance switches automatically.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum OverlaySize: String, CaseIterable, Identifiable {
    case half, full, double, triple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .half: return "Half"
        case .full: return "Default"
        case .double: return "2×"
        case .triple: return "3×"
        }
    }

    /// `SplitFlapClockFace` scale factor. Tuned so "Default" lands close
    /// to a standard macOS medium desktop widget's width, not the old
    /// fixed scale-3 render that dwarfed every other widget on the
    /// desktop. 2×/3× scale up from that same baseline.
    var scale: CGFloat {
        switch self {
        case .half: return 0.325
        case .full: return 0.65
        case .double: return 1.3
        case .triple: return 1.95
        }
    }
}

enum TimeFormat: String, CaseIterable, Identifiable {
    case twelveHour, twentyFourHour

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twelveHour: return "12-hour"
        case .twentyFourHour: return "24-hour"
        }
    }
}

enum MeridiemStyle: String, CaseIterable, Identifiable {
    case text, icon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "AM/PM"
        case .icon: return "Sun/Moon"
        }
    }

    /// The flip card's displayed value for a given AM/PM state. Plain
    /// Unicode symbols (not SF Symbols) — the card renders its face via
    /// CoreText same as digits, so any glyph the system font supports
    /// works without a separate image-rendering path.
    func value(isPM: Bool) -> String {
        switch self {
        case .text: return isPM ? "PM" : "AM"
        case .icon: return isPM ? "🌙" : "☀️"
        }
    }
}

/// Single source of truth for user-facing preferences, backed by
/// UserDefaults and exposed as Combine-observable so both SwiftUI (via
/// `SettingsView`) and plain AppKit controllers (`OverlayWindowController`)
/// can react to changes.
final class AppSettings: ObservableObject {
    @Published var showDesktopOverlay: Bool {
        didSet { UserDefaults.standard.set(showDesktopOverlay, forKey: Keys.showDesktopOverlay) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// 0 = solid (opaque), 1 = fully clear glass. Drives the scrim opacity
    /// layered over the popover's `NSVisualEffectView` in
    /// `VibrantHostingController`.
    @Published var popoverGlassiness: Double {
        didSet { UserDefaults.standard.set(popoverGlassiness, forKey: Keys.popoverGlassiness) }
    }

    @Published var overlaySize: OverlaySize {
        didSet { UserDefaults.standard.set(overlaySize.rawValue, forKey: Keys.overlaySize) }
    }

    @Published var meridiemStyle: MeridiemStyle {
        didSet { UserDefaults.standard.set(meridiemStyle.rawValue, forKey: Keys.meridiemStyle) }
    }

    @Published var showSecondClock: Bool {
        didSet { UserDefaults.standard.set(showSecondClock, forKey: Keys.showSecondClock) }
    }

    /// `TimeZone` identifier (e.g. "America/New_York") for the second
    /// menu-bar clock.
    @Published var secondTimezoneID: String {
        didSet { UserDefaults.standard.set(secondTimezoneID, forKey: Keys.secondTimezoneID) }
    }

    @Published var timeFormat: TimeFormat {
        didSet { UserDefaults.standard.set(timeFormat.rawValue, forKey: Keys.timeFormat) }
    }

    @Published var showDateOnOverlay: Bool {
        didSet { UserDefaults.standard.set(showDateOnOverlay, forKey: Keys.showDateOnOverlay) }
    }

    /// When true, the desktop clock slowly drifts and bounces around the
    /// screen on its own (like a DVD-logo screensaver) instead of sitting
    /// still where dragged.
    @Published var floatAcrossScreen: Bool {
        didSet { UserDefaults.standard.set(floatAcrossScreen, forKey: Keys.floatAcrossScreen) }
    }

    private enum Keys {
        static let showDesktopOverlay = "showDesktopOverlay"
        static let launchAtLogin = "launchAtLogin"
        static let theme = "theme"
        static let popoverGlassiness = "popoverGlassiness"
        static let overlaySize = "overlaySize"
        static let meridiemStyle = "meridiemStyle"
        static let showSecondClock = "showSecondClock"
        static let secondTimezoneID = "secondTimezoneID"
        static let timeFormat = "timeFormat"
        static let showDateOnOverlay = "showDateOnOverlay"
        static let floatAcrossScreen = "floatAcrossScreen"
    }

    init() {
        let defaults = UserDefaults.standard
        showDesktopOverlay = defaults.object(forKey: Keys.showDesktopOverlay) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        theme = (defaults.string(forKey: Keys.theme)).flatMap(AppTheme.init(rawValue:)) ?? .system
        popoverGlassiness = defaults.object(forKey: Keys.popoverGlassiness) as? Double ?? 0.7
        overlaySize = (defaults.string(forKey: Keys.overlaySize)).flatMap(OverlaySize.init(rawValue:)) ?? .full
        meridiemStyle = (defaults.string(forKey: Keys.meridiemStyle)).flatMap(MeridiemStyle.init(rawValue:)) ?? .text
        showSecondClock = defaults.object(forKey: Keys.showSecondClock) as? Bool ?? false
        secondTimezoneID = defaults.string(forKey: Keys.secondTimezoneID) ?? "UTC"
        timeFormat = (defaults.string(forKey: Keys.timeFormat)).flatMap(TimeFormat.init(rawValue:)) ?? .twelveHour
        showDateOnOverlay = defaults.object(forKey: Keys.showDateOnOverlay) as? Bool ?? true
        floatAcrossScreen = defaults.object(forKey: Keys.floatAcrossScreen) as? Bool ?? false
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Not a system-boundary failure worth surfacing to the user —
            // login-item registration failing just means the toggle didn't
            // take effect; log for debugging.
            print("AppSettings: launch-at-login registration failed: \(error)")
        }
    }
}
