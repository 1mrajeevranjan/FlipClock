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
        XCTAssertTrue(settings.worldClocks.isEmpty)
        XCTAssertEqual(settings.timeFormat, .twelveHour)
        XCTAssertEqual(settings.widgetColorStyle, .full)
    }

    func testChangesPersistAcrossANewInstanceReadingTheSameSuite() {
        let first = AppSettings(defaults: defaults)
        first.theme = .dark
        first.overlaySize = .double
        first.addWorldClock(timezoneID: "Asia/Tokyo")
        first.worldClocks[0].customLabel = "HQ"
        first.worldClocks[0].widgetSize = .triple
        first.worldClocks[0].timeFormat = .twentyFourHour
        first.timeFormat = .twentyFourHour

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertEqual(second.overlaySize, .double)
        XCTAssertEqual(second.worldClocks, first.worldClocks)
        XCTAssertEqual(second.timeFormat, .twentyFourHour)
    }

    func testWorldClockDisplayRoundTripsAllFourStates() {
        var clock = WorldClock(timezoneID: "UTC")
        for display in WorldClockDisplay.allCases {
            clock.display = display
            XCTAssertEqual(clock.display, display, "round-trip failed for \(display)")
            XCTAssertEqual(clock.showsInMenuBar, display.showsInMenuBar)
            XCTAssertEqual(clock.showsAsWidget, display.showsAsWidget)
        }
    }

    func testWorldClocksAreCappedAtFive() {
        let settings = AppSettings(defaults: defaults)
        for _ in 0..<(WorldClock.maxCount + 2) { settings.addWorldClock() }
        XCTAssertEqual(settings.worldClocks.count, WorldClock.maxCount)
        XCTAssertFalse(settings.canAddWorldClock)

        settings.removeWorldClock(id: settings.worldClocks[1].id)
        XCTAssertEqual(settings.worldClocks.count, WorldClock.maxCount - 1)
        XCTAssertTrue(settings.canAddWorldClock)
    }

    /// Users of the single-second-clock version keep their clock, carried
    /// over with the size and format it used to share with the main clock.
    func testLegacySecondClockMigratesToTheFirstWorldClock() {
        defaults.set(true, forKey: "showSecondClock")
        defaults.set(true, forKey: "showSecondClockOverlay")
        defaults.set("Europe/London", forKey: "secondTimezoneID")
        defaults.set(OverlaySize.double.rawValue, forKey: "overlaySize")
        defaults.set(TimeFormat.twentyFourHour.rawValue, forKey: "timeFormat")

        let clocks = AppSettings(defaults: defaults).worldClocks
        XCTAssertEqual(clocks.count, 1)
        XCTAssertEqual(clocks.first?.timezoneID, "Europe/London")
        XCTAssertEqual(clocks.first?.display, .both)
        XCTAssertEqual(clocks.first?.widgetSize, .double)
        XCTAssertEqual(clocks.first?.timeFormat, .twentyFourHour)
    }

    func testSwitchedOffLegacySecondClockIsNotMigrated() {
        defaults.set(false, forKey: "showSecondClock")
        defaults.set("Europe/London", forKey: "secondTimezoneID")
        XCTAssertTrue(AppSettings(defaults: defaults).worldClocks.isEmpty)
    }

    /// World clocks drop seconds in the menu bar so they fit beside the main
    /// clock on a notched display.
    func testMenuBarWorldClockIsNarrowerThanTheMainClock() {
        let main = MenuBarClockView.itemSize(timeFormat: .twelveHour).width
        let world = WorldClockMenuBarView.itemSize(label: "GMT", timeFormat: .twelveHour).width
        XCTAssertLessThan(world, main)
    }

    func testWorldClockNamesAndOffsets() {
        var clock = WorldClock(timezoneID: "America/New_York")
        XCTAssertEqual(clock.displayName, "New York")
        XCTAssertEqual(clock.menuBarLabel, "NEW YORK")

        clock.customLabel = "  Mom  "
        XCTAssertEqual(clock.displayName, "Mom")

        clock.customLabel = "Headquarters East"
        XCTAssertEqual(clock.menuBarLabel.count, WorldClock.menuBarLabelLimit)
        XCTAssertTrue(clock.menuBarLabel.hasSuffix("…"))

        XCTAssertEqual(WorldClock.offsetLabel(for: TimeZone(identifier: "Asia/Kolkata")!), "UTC+05:30")
        XCTAssertEqual(WorldClock.offsetLabel(for: TimeZone(identifier: "UTC")!), "UTC+00:00")
        let winter = Date(timeIntervalSince1970: 1_705_000_000) // Jan 2024, no DST
        XCTAssertEqual(WorldClock.offsetLabel(for: TimeZone(identifier: "America/St_Johns")!, at: winter), "UTC-03:30")
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

    func testAutomaticDimmingFollowsDesktopFocus() {
        for focused in [true, false] {
            XCTAssertFalse(SystemWidgetDimming.never.dims(desktopFocused: focused))
            XCTAssertTrue(SystemWidgetDimming.always.dims(desktopFocused: focused))
        }
        XCTAssertTrue(SystemWidgetDimming.automatic.dims(desktopFocused: false))
        XCTAssertFalse(SystemWidgetDimming.automatic.dims(desktopFocused: true))
    }

    /// Matched against the system widgets side by side: Finder in front with
    /// another app's window still on screen leaves them dimmed; they turn
    /// vivid only once clicking the wallpaper has slid every window aside.
    func testDesktopFocusNeedsFinderFrontAndEveryWindowSlidAside() {
        let screen = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        let onScreen = DesktopFocus.WindowInfo(layer: 0, bounds: CGRect(x: 100, y: 100, width: 500, height: 400), alpha: 1)
        let slidAside = DesktopFocus.WindowInfo(layer: 0, bounds: CGRect(x: 960, y: 100, width: 500, height: 400), alpha: 1)
        let finder = DesktopFocus.finderBundleID

        XCTAssertFalse(DesktopFocus.isFocused(frontmostBundleID: "com.apple.Safari", windows: [], screens: screen))
        XCTAssertTrue(DesktopFocus.isFocused(frontmostBundleID: finder, windows: [], screens: screen))
        XCTAssertFalse(DesktopFocus.isFocused(frontmostBundleID: finder, windows: [onScreen], screens: screen))
        XCTAssertTrue(DesktopFocus.isFocused(frontmostBundleID: finder, windows: [slidAside], screens: screen))
    }

    func testClickTargetTellsWallpaperFromWindowsAndIgnoresChrome() {
        let visible = [CGRect(x: 0, y: 33, width: 1000, height: 700)]
        let wallpaper = DesktopFocus.WindowInfo(layer: -2147483624, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), alpha: 1)
        let app = DesktopFocus.WindowInfo(layer: 0, bounds: CGRect(x: 100, y: 100, width: 300, height: 300), alpha: 1)
        let widget = DesktopFocus.WindowInfo(layer: -2147483601, bounds: CGRect(x: 600, y: 100, width: 200, height: 200), alpha: 1)
        // The Dock and notch utilities cover the whole screen with transparent
        // windows that clicks pass through; they must not swallow every click.
        let dockOverlay = DesktopFocus.WindowInfo(layer: 20, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), alpha: 1)
        let notchOverlay = DesktopFocus.WindowInfo(layer: 27, bounds: CGRect(x: 300, y: 0, width: 400, height: 210), alpha: 1)
        let stack = [notchOverlay, dockOverlay, app, widget, wallpaper]

        XCTAssertEqual(DesktopFocus.clickTarget(at: CGPoint(x: 500, y: 600), windows: stack, visibleFrames: visible), true)
        XCTAssertEqual(DesktopFocus.clickTarget(at: CGPoint(x: 450, y: 150), windows: stack, visibleFrames: visible), true)
        XCTAssertEqual(DesktopFocus.clickTarget(at: CGPoint(x: 200, y: 200), windows: stack, visibleFrames: visible), false)
        XCTAssertNil(DesktopFocus.clickTarget(at: CGPoint(x: 200, y: 10), windows: stack, visibleFrames: visible), "menu bar")
        XCTAssertNil(DesktopFocus.clickTarget(at: CGPoint(x: 500, y: 780), windows: stack, visibleFrames: visible), "Dock strip")
        XCTAssertNil(DesktopFocus.clickTarget(at: CGPoint(x: 700, y: 200), windows: stack, visibleFrames: visible), "widget")
    }

    func testOnlyWallpaperLevelWindowsFeedTheBackdrop() {
        XCTAssertTrue(DesktopBackdropCapture.isWallpaperLayer(-2147483624))
        XCTAssertFalse(DesktopBackdropCapture.isWallpaperLayer(Int(CGWindowLevelForKey(.desktopIconWindow))))
        XCTAssertFalse(DesktopBackdropCapture.isWallpaperLayer(0))
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
