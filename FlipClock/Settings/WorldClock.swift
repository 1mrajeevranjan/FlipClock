import Foundation

/// One extra time-zone clock beside the main (local) one. Each can appear in
/// the menu bar, as a desktop widget, or both, with its own widget size and
/// 12/24-hour format; font, theme, colour style and the date row stay shared
/// with the main clock so every clock reads as one family.
struct WorldClock: Codable, Identifiable, Equatable {
    static let maxCount = 5

    var id = UUID()
    var timezoneID: String
    /// User-chosen name ("Mom", "HQ"). Empty means "use the city".
    var customLabel: String = ""
    var showsInMenuBar: Bool = true
    var showsAsWidget: Bool = false
    var widgetSize: OverlaySize = .full
    var timeFormat: TimeFormat = .twelveHour

    var timeZone: TimeZone { TimeZone(identifier: timezoneID) ?? .current }

    /// What the clock is called everywhere it appears — the custom label if
    /// there is one, otherwise the city from the zone identifier
    /// ("America/New_York" -> "New York").
    var displayName: String {
        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.cityName(for: timezoneID) : trimmed
    }

    var display: WorldClockDisplay {
        get { WorldClockDisplay(showsInMenuBar: showsInMenuBar, showsAsWidget: showsAsWidget) }
        set {
            showsInMenuBar = newValue.showsInMenuBar
            showsAsWidget = newValue.showsAsWidget
        }
    }

    static func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// "UTC+05:30" — for the current moment, so it follows daylight saving.
    static func offsetLabel(for timeZone: TimeZone, at date: Date = Date()) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        return String(format: "UTC%@%02d:%02d", sign, magnitude / 3600, (magnitude / 60) % 60)
    }

    /// The short tag shown beside the digits in the menu bar. Capped so one
    /// long custom name can't crowd other status items out of the bar.
    static let menuBarLabelLimit = 10

    var menuBarLabel: String {
        let name = displayName.uppercased()
        guard name.count > Self.menuBarLabelLimit else { return name }
        return String(name.prefix(Self.menuBarLabelLimit - 1)) + "…"
    }
}
