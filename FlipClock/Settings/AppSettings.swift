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

/// Where the second (extra-timezone) clock appears — UI-only grouping over
/// `AppSettings.showSecondClock`/`showSecondClockOverlay` so the settings
/// screen offers one choice instead of two toggles whose four combinations
/// (both off, only one on, both on) weren't obviously distinct controls.
enum SecondClockDisplay: String, CaseIterable, Identifiable {
    case off, menuBar, widget, both

    var id: String { rawValue }

    /// Kept short on purpose. A SwiftUI segmented `Picker` sizes itself to its
    /// labels and will not compress them, so "Desktop Widget" pushed the whole
    /// control wider than the settings window and clipped "Both" off the right
    /// edge. "Widget" is unambiguous next to "Menu Bar" under a
    /// "Show second clock" heading.
    var label: String {
        switch self {
        case .off: return "Off"
        case .menuBar: return "Menu Bar"
        case .widget: return "Widget"
        case .both: return "Both"
        }
    }

    var showsInMenuBar: Bool { self == .menuBar || self == .both }
    var showsAsWidget: Bool { self == .widget || self == .both }

    init(showsInMenuBar: Bool, showsAsWidget: Bool) {
        switch (showsInMenuBar, showsAsWidget) {
        case (false, false): self = .off
        case (true, false): self = .menuBar
        case (false, true): self = .widget
        case (true, true): self = .both
        }
    }
}

enum WidgetColorStyle: String, CaseIterable, Identifiable {
    case full, monochrome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return "Full Color"
        case .monochrome: return "Monochrome"
        }
    }
}

/// macOS's System Settings > Desktop & Dock > Widgets > "Dim widgets on
/// desktop" control, which the real desktop widgets follow. Dimmed is the
/// washed-out, desaturated state Calendar/Weather/Battery drop into; undimmed
/// is the vivid, near-opaque one. A desktop widget that stays vivid while the
/// system's own are dimmed immediately looks foreign next to them.
///
/// The raw values are macOS's and are **not** in the popup's visual order —
/// verified by driving the real control and reading the stored number back
/// after each choice, which is the only way to get this right. Guessing from
/// menu order gives Never and Always exactly backwards.
enum SystemWidgetDimming: Int {
    case always = 0
    case never = 1
    case automatic = 2

    static let domain = "com.apple.widgets"
    static let key = "widgetAppearance"

    /// `automatic` is grouped with `always` rather than with `never`: it means
    /// "dim while an app is in front", and for a desktop widget that's nearly
    /// all the time — in testing the system's own widgets rendered dimmed
    /// under `automatic` in every state that could be captured, including with
    /// the Finder frontmost. There's no public API for the live dim state, so
    /// matching the common case beats leaving the widget vivid and obviously
    /// out of place.
    var drainsColor: Bool { self != .never }

    /// Reads the live system value. `CFPreferencesAppSynchronize` first
    /// because this is another process's domain — without it the value is
    /// served from a cache captured at first read and never sees the user
    /// changing the setting.
    static func current() -> SystemWidgetDimming {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let raw = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int,
              let value = SystemWidgetDimming(rawValue: raw) else { return .automatic }
        return value
    }
}

/// Single source of truth for user-facing preferences, backed by
/// UserDefaults and exposed as Combine-observable so both SwiftUI (via
/// `SettingsView`) and plain AppKit controllers (`OverlayWindowController`)
/// can react to changes.
final class AppSettings: ObservableObject {
    /// Injectable so tests can pass an isolated `UserDefaults(suiteName:)`
    /// instead of touching the real user's `.standard` — every persisted
    /// property below reads/writes through this rather than
    /// `UserDefaults.standard` directly.
    private let defaults: UserDefaults

    @Published var showDesktopOverlay: Bool {
        didSet { defaults.set(showDesktopOverlay, forKey: Keys.showDesktopOverlay) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var overlaySize: OverlaySize {
        didSet { defaults.set(overlaySize.rawValue, forKey: Keys.overlaySize) }
    }

    @Published var meridiemStyle: MeridiemStyle {
        didSet { defaults.set(meridiemStyle.rawValue, forKey: Keys.meridiemStyle) }
    }

    @Published var showSecondClock: Bool {
        didSet { defaults.set(showSecondClock, forKey: Keys.showSecondClock) }
    }

    /// `TimeZone` identifier (e.g. "America/New_York") for the second
    /// menu-bar clock.
    @Published var secondTimezoneID: String {
        didSet { defaults.set(secondTimezoneID, forKey: Keys.secondTimezoneID) }
    }

    /// When true, a second desktop widget shows `secondTimezoneID`'s time —
    /// same glass-widget treatment as the primary desktop clock, labeled
    /// with the timezone name.
    @Published var showSecondClockOverlay: Bool {
        didSet { defaults.set(showSecondClockOverlay, forKey: Keys.showSecondClockOverlay) }
    }

    /// Single settings-UI-facing view over `showSecondClock` +
    /// `showSecondClockOverlay` — not itself persisted, just a convenience
    /// for presenting "Off/Menu Bar/Desktop Widget/Both" as one control.
    var secondClockDisplay: SecondClockDisplay {
        get { SecondClockDisplay(showsInMenuBar: showSecondClock, showsAsWidget: showSecondClockOverlay) }
        set {
            showSecondClock = newValue.showsInMenuBar
            showSecondClockOverlay = newValue.showsAsWidget
        }
    }

    @Published var timeFormat: TimeFormat {
        didSet { defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat) }
    }

    @Published var showDateOnOverlay: Bool {
        didSet { defaults.set(showDateOnOverlay, forKey: Keys.showDateOnOverlay) }
    }

    /// When true, the desktop clock slowly drifts and bounces around the
    /// screen on its own (like a DVD-logo screensaver) instead of sitting
    /// still where dragged.
    @Published var floatAcrossScreen: Bool {
        didSet { defaults.set(floatAcrossScreen, forKey: Keys.floatAcrossScreen) }
    }

    /// When true, the desktop overlay window covers the entire screen
    /// (edge to edge, square corners) instead of sizing itself to the
    /// clock content — the glass background becomes a full-screen liquid
    /// glass layer with the clock centered on top. Mutually exclusive
    /// with float-across-screen (a full-screen window has nowhere to
    /// drift to).
    @Published var fillScreen: Bool {
        didSet {
            defaults.set(fillScreen, forKey: Keys.fillScreen)
            if fillScreen { floatAcrossScreen = false }
        }
    }

    /// Persisted by `WidgetFont.id` (a stable string), looked up against
    /// `WidgetFont.all` — that list can grow without invalidating
    /// previously-saved preferences the way an enum `rawValue` would.
    @Published var widgetFont: WidgetFont {
        didSet { defaults.set(widgetFont.id, forKey: Keys.widgetFont) }
    }

    /// Mirrors macOS's own desktop-widget "Full Color / Monochrome" style
    /// picker — desaturates the glass background's blurred backdrop so
    /// the widget reads as grayscale-tinted glass instead of a color
    /// photo diffused behind it.
    @Published var widgetColorStyle: WidgetColorStyle {
        didSet { defaults.set(widgetColorStyle.rawValue, forKey: Keys.widgetColorStyle) }
    }

    /// Mirror of the system's widget-dimming setting (see
    /// `SystemWidgetDimming`), refreshed by
    /// `startWatchingSystemWidgetAppearance()`. Not persisted — it belongs to
    /// macOS, not to this app.
    @Published private(set) var systemWidgetDimming: SystemWidgetDimming = .automatic

    /// What the widget glass should actually do, combining the app's own
    /// picker with the system one. The app's Monochrome setting forces
    /// grayscale; otherwise the system's choice wins, so the widget tracks
    /// the native ones sitting next to it on the desktop.
    var widgetDrainsColor: Bool {
        widgetColorStyle == .monochrome || systemWidgetDimming.drainsColor
    }

    /// There's no public notification for the widget-style picker changing,
    /// so this polls — slowly, and only while a widget is actually on screen.
    /// Gating on visibility rather than on the feature flag alone is the rule
    /// this codebase already learned twice (see `DesktopBackdropCapture` and
    /// `OverlayWindowController`'s float timer): a timer tied to a setting but
    /// not to whether anything can be seen just burns battery forever.
    private var systemAppearanceTimer: Timer?

    func startWatchingSystemWidgetAppearance() {
        systemWidgetDimming = SystemWidgetDimming.current()
        guard systemAppearanceTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = SystemWidgetDimming.current()
            if current != self.systemWidgetDimming { self.systemWidgetDimming = current }
        }
        RunLoop.main.add(timer, forMode: .common)
        systemAppearanceTimer = timer
    }

    func stopWatchingSystemWidgetAppearance() {
        systemAppearanceTimer?.invalidate()
        systemAppearanceTimer = nil
    }

    private enum Keys {
        static let showDesktopOverlay = "showDesktopOverlay"
        static let launchAtLogin = "launchAtLogin"
        static let theme = "theme"
        static let overlaySize = "overlaySize"
        static let meridiemStyle = "meridiemStyle"
        static let showSecondClock = "showSecondClock"
        static let secondTimezoneID = "secondTimezoneID"
        static let showSecondClockOverlay = "showSecondClockOverlay"
        static let timeFormat = "timeFormat"
        static let showDateOnOverlay = "showDateOnOverlay"
        static let floatAcrossScreen = "floatAcrossScreen"
        static let fillScreen = "fillScreen"
        static let widgetFont = "widgetFont"
        static let widgetColorStyle = "widgetColorStyle"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showDesktopOverlay = defaults.object(forKey: Keys.showDesktopOverlay) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        theme = (defaults.string(forKey: Keys.theme)).flatMap(AppTheme.init(rawValue:)) ?? .system
        overlaySize = (defaults.string(forKey: Keys.overlaySize)).flatMap(OverlaySize.init(rawValue:)) ?? .full
        meridiemStyle = (defaults.string(forKey: Keys.meridiemStyle)).flatMap(MeridiemStyle.init(rawValue:)) ?? .text
        showSecondClock = defaults.object(forKey: Keys.showSecondClock) as? Bool ?? false
        secondTimezoneID = defaults.string(forKey: Keys.secondTimezoneID) ?? "UTC"
        showSecondClockOverlay = defaults.object(forKey: Keys.showSecondClockOverlay) as? Bool ?? false
        timeFormat = (defaults.string(forKey: Keys.timeFormat)).flatMap(TimeFormat.init(rawValue:)) ?? .twelveHour
        showDateOnOverlay = defaults.object(forKey: Keys.showDateOnOverlay) as? Bool ?? true
        floatAcrossScreen = defaults.object(forKey: Keys.floatAcrossScreen) as? Bool ?? false
        fillScreen = defaults.object(forKey: Keys.fillScreen) as? Bool ?? false
        widgetFont = (defaults.string(forKey: Keys.widgetFont)).map(WidgetFont.byID) ?? .system
        widgetColorStyle = (defaults.string(forKey: Keys.widgetColorStyle)).flatMap(WidgetColorStyle.init(rawValue:)) ?? .full
        // Seed it here as well as in the watcher: the watcher only runs while
        // a widget is actually on screen, but Settings can be opened without
        // one, and a stale default there would show the wrong explanation.
        systemWidgetDimming = SystemWidgetDimming.current()
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
