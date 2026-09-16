import XCTest
@testable import FlipClock

/// Every test gets its own throwaway `UserDefaults` suite — `AppSettings`
/// never touches the real user's `.standard` defaults here, so these tests
/// are safe to run against a machine that also has the real app installed
/// (this repo's own dev environment does).
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsMatchDocumentedFallbacksOnFirstLaunch() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showDesktopOverlay)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.overlaySize, .full)
        XCTAssertEqual(settings.meridiemStyle, .text)
        XCTAssertFalse(settings.showSecondClock)
        XCTAssertEqual(settings.secondTimezoneID, "UTC")
        XCTAssertEqual(settings.timeFormat, .twelveHour)
        XCTAssertEqual(settings.widgetColorStyle, .full)
    }

    func testChangesPersistAcrossANewInstanceReadingTheSameSuite() {
        let first = AppSettings(defaults: defaults)
        first.theme = .dark
        first.overlaySize = .double
        first.secondTimezoneID = "Asia/Tokyo"
        first.timeFormat = .twentyFourHour

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertEqual(second.overlaySize, .double)
        XCTAssertEqual(second.secondTimezoneID, "Asia/Tokyo")
        XCTAssertEqual(second.timeFormat, .twentyFourHour)
    }

    func testSecondClockDisplayComputedPropertyRoundTripsAllFourStates() {
        let settings = AppSettings(defaults: defaults)
        for display in SecondClockDisplay.allCases {
            settings.secondClockDisplay = display
            XCTAssertEqual(settings.secondClockDisplay, display, "round-trip failed for \(display)")
        }
    }

    func testSecondClockDisplayReflectsBothUnderlyingBooleans() {
        let settings = AppSettings(defaults: defaults)
        settings.showSecondClock = true
        settings.showSecondClockOverlay = false
        XCTAssertEqual(settings.secondClockDisplay, .menuBar)

        settings.showSecondClock = false
        settings.showSecondClockOverlay = true
        XCTAssertEqual(settings.secondClockDisplay, .widget)

        settings.showSecondClock = true
        settings.showSecondClockOverlay = true
        XCTAssertEqual(settings.secondClockDisplay, .both)

        settings.showSecondClock = false
        settings.showSecondClockOverlay = false
        XCTAssertEqual(settings.secondClockDisplay, .off)
    }

    /// `fillScreen` and `floatAcrossScreen` are documented as mutually
    /// exclusive — enabling fill-screen should force float off, since a
    /// full-screen window has nowhere to drift to.
    func testEnablingFillScreenForcesFloatAcrossScreenOff() {
        let settings = AppSettings(defaults: defaults)
        settings.floatAcrossScreen = true
        XCTAssertTrue(settings.floatAcrossScreen)

        settings.fillScreen = true
        XCTAssertFalse(settings.floatAcrossScreen, "fillScreen must force floatAcrossScreen off")
    }

    /// The inverse is NOT documented as forced — confirms current behavior
    /// so a future change to it is a deliberate decision, not silent drift.
    func testEnablingFloatAcrossScreenDoesNotForceFillScreenOff() {
        let settings = AppSettings(defaults: defaults)
        settings.fillScreen = true
        settings.floatAcrossScreen = true
        XCTAssertTrue(settings.fillScreen)
        XCTAssertTrue(settings.floatAcrossScreen)
    }

    func testCorruptedThemeValueFallsBackToSystemInsteadOfCrashing() {
        defaults.set("not-a-real-theme", forKey: "theme")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .system)
    }

    func testWidgetFontPersistsByStableIDNotArrayIndex() {
        let settings = AppSettings(defaults: defaults)
        guard let font = WidgetFont.all.first else {
            return XCTFail("WidgetFont.all must not be empty")
        }
        settings.widgetFont = font
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.widgetFont.id, font.id)
    }

    func testUnknownPersistedWidgetFontIDFallsBackToSystemInsteadOfCrashing() {
        defaults.set("this-font-id-does-not-exist-anymore", forKey: "widgetFont")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.widgetFont.id, WidgetFont.system.id)
    }

    // MARK: - System widget dimming

    /// These raw values are macOS's own and are NOT in the popup's visual
    /// order (which reads Automatically, Always, Never). They were established
    /// by driving the real System Settings control and reading the stored
    /// number back after each choice; guessing from menu order puts Never and
    /// Always exactly backwards, which silently inverts the whole feature.
    func testSystemWidgetDimmingRawValuesMatchWhatMacOSActuallyStores() {
        XCTAssertEqual(SystemWidgetDimming.always.rawValue, 0)
        XCTAssertEqual(SystemWidgetDimming.never.rawValue, 1)
        XCTAssertEqual(SystemWidgetDimming.automatic.rawValue, 2)
    }

    func testOnlyNeverKeepsTheWidgetVivid() {
        XCTAssertFalse(SystemWidgetDimming.never.drainsColor)
        XCTAssertTrue(SystemWidgetDimming.always.drainsColor)
        // Automatic means "dim while an app is in front", which for a desktop
        // widget is nearly always — it groups with always, not with never.
        XCTAssertTrue(SystemWidgetDimming.automatic.drainsColor)
    }

    /// The app's Monochrome pick and the system's dimming are deliberately
    /// different strengths: the first is an explicit request for greyscale,
    /// the second only flattens. Measuring a real dimmed widget showed its
    /// glass still in colour, so dimming must not drain to grey.
    func testAppMonochromeGoesFullGreyscaleButDimmingOnlyFlattens() {
        XCTAssertEqual(WidgetGlassBackground.saturation(monochrome: true, dimmed: false), 0)
        XCTAssertEqual(WidgetGlassBackground.saturation(monochrome: true, dimmed: true), 0)

        let dimmedSat = WidgetGlassBackground.saturation(monochrome: false, dimmed: true)
        let vividSat = WidgetGlassBackground.saturation(monochrome: false, dimmed: false)
        XCTAssertGreaterThan(dimmedSat, 0, "dimming must keep the backdrop in colour, like the system's own widgets")
        XCTAssertLessThan(dimmedSat, vividSat, "dimming must still be visibly flatter than vivid")
    }

    func testDimmingDeepensTheScrimRatherThanLeavingItUnchanged() {
        let vivid = WidgetGlassBackground.scrim(isDark: false, dimmed: false)
        let dimmed = WidgetGlassBackground.scrim(isDark: false, dimmed: true)
        XCTAssertNotEqual(vivid, dimmed)
    }
}
