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
}
