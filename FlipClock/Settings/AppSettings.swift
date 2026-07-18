import Foundation
import Combine
import ServiceManagement
import SwiftUI
import AppKit

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

    /// The card(s) the meridiem indicator splits into — two separate flip
    /// cards for text ("A"+"M"/"P"+"M", matching every other position in
    /// the clock being its own card), one for the icon style (a single
    /// glyph doesn't split meaningfully).
    func cards(isPM: Bool) -> [String] {
        switch self {
        case .text: return (isPM ? "PM" : "AM").map(String.init)
        case .icon: return [value(isPM: isPM)]
        }
    }
}

enum WidgetFont: String, CaseIterable, Identifiable {
    case system, sfMono, menlo, avenirNext, helveticaCondensed, courier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .avenirNext: return "Avenir Next"
        case .helveticaCondensed: return "Helvetica Condensed"
        case .courier: return "Courier"
        }
    }

    /// PostScript name for `NSFont(name:size:)`. `nil` means either the
    /// plain system font (`.system`) or the monospaced system font
    /// (`.sfMono`, resolved via `NSFont.monospacedSystemFont` since that's
    /// the correct API for it, not a PostScript name lookup) —
    /// `isMonospacedSystem` disambiguates the two `nil` cases.
    var postscriptName: String? {
        switch self {
        case .system, .sfMono: return nil
        case .menlo: return "Menlo-Bold"
        case .avenirNext: return "AvenirNext-Heavy"
        case .helveticaCondensed: return "HelveticaNeue-CondensedBlack"
        case .courier: return "Courier-Bold"
        }
    }

    var isMonospacedSystem: Bool { self == .sfMono }
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

    /// When true, the desktop overlay window covers the entire screen
    /// (edge to edge, square corners) instead of sizing itself to the
    /// clock content — the glass background becomes a full-screen liquid
    /// glass layer with the clock centered on top. Mutually exclusive
    /// with float-across-screen (a full-screen window has nowhere to
    /// drift to).
    @Published var fillScreen: Bool {
        didSet {
            UserDefaults.standard.set(fillScreen, forKey: Keys.fillScreen)
            if fillScreen { floatAcrossScreen = false }
        }
    }

    @Published var widgetFont: WidgetFont {
        didSet { UserDefaults.standard.set(widgetFont.rawValue, forKey: Keys.widgetFont) }
    }

    @Published var widgetTintEnabled: Bool {
        didSet { UserDefaults.standard.set(widgetTintEnabled, forKey: Keys.widgetTintEnabled) }
    }

    /// The HIG-style accent tint applied across the clock when
    /// `widgetTintEnabled` is true. Persisted as a hex string (`Color`
    /// itself isn't a `UserDefaults`-storable type) — alpha isn't part of
    /// the stored value, every consumer applies its own fixed opacity.
    @Published var widgetTintColor: Color {
        didSet { UserDefaults.standard.set(widgetTintColor.hexString, forKey: Keys.widgetTintColor) }
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
        static let fillScreen = "fillScreen"
        static let widgetFont = "widgetFont"
        static let widgetTintEnabled = "widgetTintEnabled"
        static let widgetTintColor = "widgetTintColor"
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
        fillScreen = defaults.object(forKey: Keys.fillScreen) as? Bool ?? false
        widgetFont = (defaults.string(forKey: Keys.widgetFont)).flatMap(WidgetFont.init(rawValue:)) ?? .system
        widgetTintEnabled = defaults.object(forKey: Keys.widgetTintEnabled) as? Bool ?? false
        widgetTintColor = (defaults.string(forKey: Keys.widgetTintColor)).map(Color.init(hex:)) ?? Color(hex: "007AFF")
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

private extension Color {
    /// RGB-only hex string (no alpha) for `UserDefaults` persistence —
    /// tint is always applied at a fixed opacity by each renderer, not by
    /// the stored color itself.
    var hexString: String {
        guard let converted = NSColor(self).usingColorSpace(.deviceRGB) else { return "007AFF" }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        let red = Double((rgb & 0xFF0000) >> 16) / 255
        let green = Double((rgb & 0x00FF00) >> 8) / 255
        let blue = Double(rgb & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
