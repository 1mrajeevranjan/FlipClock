import XCTest
import AppKit
@testable import FlipClock

/// Covers the hot paths that run continuously while the app is alive
/// (once/second time-engine math, per-render digit diffing) and the pure
/// decision functions that gate the app's most expensive operation
/// (`DesktopBackdropCapture`'s screen-capture + Gaussian blur). These don't
/// assert specific wall-clock thresholds (`measure` already fails a test on
/// significant regression against its own baseline) — they exist to catch a
/// future change that makes a per-tick/per-render computation accidentally
/// quadratic or newly allocation-heavy.
final class PerformanceTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    @MainActor
    func testDigitCacheReusesFacesWithoutMixingStylesOrHalves() {
        let size = CGSize(width: 30, height: 48)
        let face = DigitFaceRenderer.face(for: "6", size: size, isDark: false)
        XCTAssertTrue(face === DigitFaceRenderer.face(for: "6", size: size, isDark: false))
        XCTAssertFalse(face === DigitFaceRenderer.face(for: "6", size: size, isDark: true))
        let top = DigitFaceRenderer.halfFace(for: "6", cardSize: size, top: true, isDark: false)
        XCTAssertTrue(top === DigitFaceRenderer.halfFace(for: "6", cardSize: size, top: true, isDark: false))
        XCTAssertFalse(top === DigitFaceRenderer.halfFace(for: "6", cardSize: size, top: false, isDark: false))
        XCTAssertEqual(top.height * 2, face.height)
    }

    func testDateCardsIgnoreSecondTicksButRefreshAtLocalMidnightAndStyleChanges() {
        let date = ISO8601DateFormatter().date(from: "2026-01-15T23:59:30Z")!
        var row = DateFlapRow(date: date, scale: 1, isDark: false, timeZone: utc)
        var next = row
        next = DateFlapRow(date: date.addingTimeInterval(1), scale: 1, isDark: false, timeZone: utc)
        XCTAssertEqual(row, next)
        next = DateFlapRow(date: date.addingTimeInterval(60), scale: 1, isDark: false, timeZone: utc)
        XCTAssertNotEqual(row, next)
        let india = TimeZone(identifier: "Asia/Kolkata")!
        row = DateFlapRow(date: date, scale: 1, isDark: false, timeZone: india)
        next = DateFlapRow(date: date.addingTimeInterval(60), scale: 1, isDark: false, timeZone: india)
        XCTAssertEqual(row, next, "UTC midnight must not redraw a different zone's unchanged date")
        next = DateFlapRow(date: date, scale: 1, isDark: true, timeZone: india)
        XCTAssertNotEqual(row, next)
    }

    func testConcurrentBackdropRequestsShareCaptureAndRespectCacheParameters() async throws {
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                           bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let probe = BackdropCaptureProbe(image: image)
        let shared = SharedBackdrop(capture: { request in await probe.capture(request) })
        async let first = shared.backdrop(displayID: 1, blurRadius: 4, dimmedBlurRadius: 12, pixelScale: 1)
        async let second = shared.backdrop(displayID: 1, blurRadius: 4, dimmedBlurRadius: 12, pixelScale: 1)
        async let third = shared.backdrop(displayID: 1, blurRadius: 4, dimmedBlurRadius: 12, pixelScale: 1, force: true)
        let results = await [first, second, third]
        XCTAssertTrue(results.allSatisfy { $0?.vivid === image })
        var count = await probe.requests.count
        XCTAssertEqual(count, 1, "Concurrent widgets must share capture and blur work across actor suspension")
        _ = await shared.backdrop(displayID: 1, blurRadius: 4, dimmedBlurRadius: 12, pixelScale: 1)
        count = await probe.requests.count
        XCTAssertEqual(count, 1)
        _ = await shared.backdrop(displayID: 1, blurRadius: 4, dimmedBlurRadius: 12, pixelScale: 2)
        count = await probe.requests.count
        XCTAssertEqual(count, 2, "Changing resolution invalidates the capture cache")
        _ = await shared.backdrop(displayID: 1, blurRadius: 8, dimmedBlurRadius: 12, pixelScale: 2)
        count = await probe.requests.count
        XCTAssertEqual(count, 3)
        _ = await shared.backdrop(displayID: 1, blurRadius: 8, dimmedBlurRadius: 12, pixelScale: 2, force: true)
        count = await probe.requests.count
        XCTAssertEqual(count, 4, "A later forced refresh still replaces cached wallpaper")
    }

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal
    }

    // MARK: - Time engine (runs every second the app is running)

    func testClockTickComputationPerformance() {
        let cal = calendar()
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 0, second: 0))!
        measure {
            for i in 0..<10_000 {
                let date = base.addingTimeInterval(TimeInterval(i))
                _ = ClockTick.at(date: date, calendar: cal)
            }
        }
    }

    func testDigitDeltaDiffPerformance() {
        let cal = calendar()
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 0, second: 0))!
        var previous: ClockTick?
        let ticks = (0..<10_000).map { i in
            ClockTick.at(date: base.addingTimeInterval(TimeInterval(i)), calendar: cal)
        }
        measure {
            previous = nil
            for tick in ticks {
                let delta = DigitDelta.diff(from: previous, to: tick)
                previous = tick
                XCTAssertNotNil(delta)
            }
        }
    }

    // MARK: - DesktopBackdropCapture pure gates (drives the single most
    // expensive operation in the app — see architecture.md Phase 6)

    func testShouldCaptureIsTrueOnlyWhenWindowIsActuallyVisible() {
        XCTAssertTrue(DesktopBackdropCapture.shouldCapture(occlusionState: .visible))
        XCTAssertFalse(DesktopBackdropCapture.shouldCapture(occlusionState: []))
    }

    func testRefreshIntervalStretchesOutUnderLowPowerMode() {
        XCTAssertEqual(DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: false), 60.0)
        XCTAssertEqual(DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: true), 180.0)
        XCTAssertGreaterThan(
            DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: true),
            DesktopBackdropCapture.refreshInterval(isLowPowerModeEnabled: false)
        )
    }

    // MARK: - Backdrop crop geometry
    //
    // The widget's glass is a crop out of a full-display capture, recomputed
    // on every drag event. Cocoa screen coordinates are bottom-left origin
    // and the captured image is top-left origin, so this flips the Y axis —
    // the one bit of arithmetic here that silently produces a plausible but
    // wrong-looking backdrop if it's off.

    func testCropRectFlipsYAndScalesToImagePixels() {
        // 1000x800pt screen at 2x, window 100pt from the left and with its
        // top edge 100pt below the top of the screen.
        let crop = DesktopBackdropCapture.cropRect(
            windowFrame: CGRect(x: 100, y: 500, width: 200, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            pixelScale: 2,
            imageSize: CGSize(width: 2000, height: 1600)
        )
        XCTAssertEqual(crop, CGRect(x: 200, y: 200, width: 400, height: 400))
    }

    func testCropRectOffsetsByScreenOriginForASecondaryDisplay() {
        // A display whose origin isn't (0,0): the crop must be relative to
        // that display's own frame, not the global coordinate space.
        let crop = DesktopBackdropCapture.cropRect(
            windowFrame: CGRect(x: 1100, y: 500, width: 200, height: 200),
            screenFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
            pixelScale: 2,
            imageSize: CGSize(width: 2000, height: 1600)
        )
        XCTAssertEqual(crop, CGRect(x: 200, y: 200, width: 400, height: 400))
    }

    func testCropRectClampsAWidgetDraggedPastTheScreenEdge() {
        // Half off the left edge. `CGImage.cropping(to:)` returns nil for a
        // rect that isn't fully inside the image, which would drop the glass
        // entirely mid-drag — so this has to come back clamped, not whole.
        let crop = DesktopBackdropCapture.cropRect(
            windowFrame: CGRect(x: -100, y: 500, width: 200, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            pixelScale: 2,
            imageSize: CGSize(width: 2000, height: 1600)
        )
        XCTAssertEqual(crop, CGRect(x: 0, y: 200, width: 200, height: 400))
    }

    func testCropRectIsNilWhenTheWidgetIsEntirelyOffTheDisplay() {
        XCTAssertNil(DesktopBackdropCapture.cropRect(
            windowFrame: CGRect(x: -500, y: 500, width: 200, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            pixelScale: 2,
            imageSize: CGSize(width: 2000, height: 1600)
        ))
    }

    // MARK: - Reminder persistence under load (JSON encode/decode is the
    // ReminderStore's per-mutation cost — see ReminderStoreTests for
    // correctness; this covers throughput on a large reminder set)

    func testReminderStoreBulkAddPerformance() {
        let suiteName = "PerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReminderStore(defaults: defaults)

        measure {
            for i in 0..<200 {
                store.add(title: "Reminder \(i)", date: Date().addingTimeInterval(TimeInterval(i * 60)))
            }
            for reminder in store.reminders {
                store.remove(reminder)
            }
        }
    }

    // MARK: - AppSettings persistence (every toggle in Settings round-trips
    // through UserDefaults synchronously on the main thread)

    func testAppSettingsPersistenceRoundTripPerformance() {
        let suiteName = "PerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        measure {
            for _ in 0..<500 {
                settings.showDesktopOverlay.toggle()
            }
        }
    }
}

private actor BackdropCaptureProbe {
    let image: CGImage
    private(set) var requests: [SharedBackdrop.CaptureRequest] = []

    init(image: CGImage) { self.image = image }

    func capture(_ request: SharedBackdrop.CaptureRequest) async -> BackdropPair {
        requests.append(request)
        try? await Task.sleep(for: .milliseconds(30))
        return BackdropPair(vivid: image, dimmed: image)
    }
}
