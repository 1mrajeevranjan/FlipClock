import XCTest
import SwiftUI
import AppKit
@testable import FlipClock

final class WidgetLayoutTests: XCTestCase {
    @MainActor
    func testCalendarReminderActionIsBlueOnFirstInactiveRender() throws {
        let suite = "CalendarActionRendering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let store = ReminderStore(defaults: defaults)
        let content = CalendarMonthView(reminderStore: store,
                                        navigation: .constant(CalendarNavigation(date: today)), today: today)
            .frame(width: 376)
            .padding(16)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .inactive)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let cgImage = try XCTUnwrap(renderer.cgImage)
        let attachment = XCTAttachment(image: NSImage(cgImage: cgImage, size: .zero))
        attachment.name = "Calendar first-open reminder action"
        attachment.lifetime = .keepAlways
        add(attachment)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var bluePixels = 0
        for y in max(0, bitmap.pixelsHigh - 90)..<bitmap.pixelsHigh {
            for x in (bitmap.pixelsWide / 2)..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > color.redComponent + 0.25 && color.greenComponent > color.redComponent + 0.1 {
                    bluePixels += 1
                }
            }
        }
        XCTAssertGreaterThan(bluePixels, 300, "The enabled Add Reminder action must retain its blue emphasis before another control is clicked")
    }

    @MainActor
    func testTimerLensMagnifiesOnlyNumbersInsideItsBand() {
        XCTAssertEqual(TimeWheelReel.magnification(atRowDistance: 0), 2.55, accuracy: 0.001)
        let edge = TimeWheelReel.selectionHeight / (2 * TimeWheelReel.rowHeight)
        let halfway = TimeWheelReel.magnification(atRowDistance: edge / 2)
        XCTAssertEqual(halfway, 2.1625, accuracy: 0.001)
        XCTAssertEqual(TimeWheelReel.magnification(atRowDistance: -edge / 2), halfway)
        for distance: CGFloat in [edge, 1, -1, 2, -2] {
            XCTAssertEqual(TimeWheelReel.magnification(atRowDistance: distance), 1)
        }
        var reel = TimeWheelReel(position: 30, range: 0...59, unitLabel: "min", showsUnit: true,
                                 isFocused: true, viewportHeight: TimeWheelReel.selectionHeight)
        reel.animatableData = -10
        XCTAssertEqual(reel.position, 0, "Interrupted animations must not overshoot the supported range")
        reel.animatableData = 70
        XCTAssertEqual(reel.position, 59)
    }

    /// The selected value must look like real, crisp text at the magnified size — not a
    /// stretched, warped copy of the small numeral (the old pixel-strip lens bent digits).
    @MainActor
    func testSelectedTimerNumeralIsUndistortedTextAtMagnifiedSize() throws {
        func inkMask<V: View>(_ content: V) throws -> (Set<Int>, Int) {
            let renderer = ImageRenderer(content: content
                .frame(width: 160, height: TimeWheelReel.selectionHeight)
                .background(Color.white)
                .environment(\.colorScheme, .light))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            var ink = Set<Int>()
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.5 { ink.insert(y * bitmap.pixelsWide + x) }
                }
            }
            return (ink, bitmap.pixelsWide)
        }
        let size = 16 * TimeWheelReel.maximumMagnification
        let reel = try inkMask(TimeWheelReel(position: 11, range: 0...59, unitLabel: "", showsUnit: true,
                                                  isFocused: false, viewportHeight: TimeWheelReel.selectionHeight))
        let reference = try inkMask(HStack(spacing: 4) {
            Text("11").font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                .frame(width: TimeWheelReel.numeralWidth, height: TimeWheelReel.selectionHeight)
            Text("")
        }.frame(maxWidth: .infinity))
        XCTAssertFalse(reference.0.isEmpty)
        // Compared by shape: align both on their ink bounds so a one-pixel layout rounding
        // difference doesn't read as distortion.
        func aligned(_ mask: (Set<Int>, Int)) -> Set<Int> {
            let width = mask.1
            let minX = mask.0.map { $0 % width }.min() ?? 0, minY = mask.0.map { $0 / width }.min() ?? 0
            return Set(mask.0.map { ($0 / width - minY) * width + ($0 % width - minX) })
        }
        let a = aligned(reel), b = aligned(reference)
        let overlap = Double(a.intersection(b).count) / Double(a.union(b).count)
        XCTAssertGreaterThan(overlap, 0.9, "Selected numeral differs from crisp \(Int(size))pt text (overlap \(Int(overlap * 100))%)")
    }

    @MainActor
    func testTimerLensRendersVisibleMagnifiedDigitsInBothAppearances() throws {
        func inkBounds(magnified: Bool, scheme: ColorScheme, position: CGFloat = 6) throws -> CGRect {
            let view = TimeWheelReel(position: position, range: 0...59, unitLabel: "", showsUnit: magnified,
                                     isFocused: false, viewportHeight: TimeWheelReel.selectionHeight)
                .frame(width: 160, height: TimeWheelReel.selectionHeight)
            let renderer = ImageRenderer(content: Group {
                if magnified, #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 6) {
                        view.modifier(PopoverControlSurface(tint: .orange.opacity(0.04),
                                                          cornerRadius: TimeWheelReel.selectionHeight / 2,
                                                          usesClearGlass: true))
                    }
                } else {
                    view
                }
            }
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme))
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            let attachment = XCTAttachment(image: NSImage(cgImage: cgImage, size: .zero))
            attachment.name = "Timer numeral \(scheme) \(magnified ? "lens" : "normal") at \(position)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var left = bitmap.pixelsWide, right = -1, top = bitmap.pixelsHigh, bottom = -1
            let centerX = (160.0 - 4) / 2 * renderer.scale
            let halfWidth = TimeWheelReel.numeralWidth / 2 * renderer.scale
            // Moving digits enter at the lens edges; exclude only the one-point glass rim.
            for y in 2..<(bitmap.pixelsHigh - 2) {
                for x in Int(centerX - halfWidth)..<Int(centerX + halfWidth) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.25 else { continue }
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    guard scheme == .dark ? brightness > 0.6 : brightness < 0.4 else { continue }
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
            XCTAssertGreaterThan(right, left, "The \(scheme) selected numeral must render visible ink")
            XCTAssertGreaterThan(bottom, top)
            return CGRect(x: left, y: top, width: max(0, right - left + 1), height: max(0, bottom - top + 1))
        }
        for scheme: ColorScheme in [.light, .dark] {
            let normal = try inkBounds(magnified: false, scheme: scheme)
            let lens = try inkBounds(magnified: true, scheme: scheme)
            XCTAssertGreaterThan(lens.height, normal.height * 1.2, "The lens must visibly magnify the numeral")
            let twoDigits = try inkBounds(magnified: true, scheme: scheme, position: 59)
            XCTAssertGreaterThan(twoDigits.width, lens.width * 1.5)
            XCTAssertLessThan(twoDigits.width, TimeWheelReel.numeralWidth * 2 - 2, "Magnified two-digit values must fit inside the numeric viewport")
            for position: CGFloat in [6.25, 6.5, 6.75] {
                let moving = try inkBounds(magnified: true, scheme: scheme, position: position)
                XCTAssertGreaterThan(moving.height, 0, "Digits must remain visible between selected values")
            }
        }
    }

    @MainActor
    func testPopoverMaterialFollowsThemeChangesWithoutOneSelectionLag() throws {
        let suite = "PopoverAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.theme = .light
        let controller = VibrantHostingController(rootView: Text("Clock"), settings: settings)
        let effect = try XCTUnwrap(controller.view as? NSVisualEffectView)
        XCTAssertEqual(effect.material, .popover)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        XCTAssertEqual(effect.appearance?.name, .aqua)
        settings.theme = .dark
        XCTAssertEqual(effect.appearance?.name, .darkAqua)
        settings.theme = .light
        XCTAssertEqual(effect.appearance?.name, .aqua)
        settings.theme = .system
        XCTAssertNil(effect.appearance)
    }

    @MainActor
    func testStopwatchPacesTheVeryFirstHundredthsFlip() {
        let digit = FlapAnimatingNSView(value: "0")
        digit.show("3", expectedChangeInterval: Stopwatch.updateInterval)
        XCTAssertLessThan(0.33 * digit.durationScale, Stopwatch.updateInterval)
        XCTAssertGreaterThan(0.33 * digit.durationScale, Stopwatch.updateInterval * 0.5)
        digit.show("6", expectedChangeInterval: Stopwatch.updateInterval)
        XCTAssertLessThan(0.33 * digit.durationScale, Stopwatch.updateInterval)
        let tens = FlapAnimatingNSView(value: "0")
        tens.show("1", expectedChangeInterval: 0.1)
        XCTAssertLessThan(0.33 * tens.durationScale, 0.1)
    }

    func testReminderFooterSizesAtEveryWidgetScale() {
        for size in OverlaySize.allCases {
            let base = OverlayContentView.windowSize(scale: size.scale, showDate: true, showMeridiem: true)
            let one = OverlayContentView.windowSize(scale: size.scale, showDate: true, showMeridiem: true, reminderCount: 1)
            let two = OverlayContentView.windowSize(scale: size.scale, showDate: true, showMeridiem: true, reminderCount: 2)
            let more = OverlayContentView.windowSize(scale: size.scale, showDate: true, showMeridiem: true, reminderCount: 10)
            XCTAssertEqual(base.width, more.width)
            XCTAssertGreaterThan(one.height, base.height)
            XCTAssertGreaterThan(two.height, one.height)
            XCTAssertGreaterThan(more.height, two.height)
            XCTAssertEqual(OverlayContentView.reminderFooterHeight(scale: size.scale, count: 3),
                           OverlayContentView.reminderFooterHeight(scale: size.scale, count: 10))
        }
    }

    func testDefaultSizeMarginIsConcentricAndMatchesHIG() {
        let scale = OverlaySize.full.scale
        let padding = OverlayContentView.padding(scale: scale)
        XCTAssertEqual(padding, 16, accuracy: 0.5)
        XCTAssertEqual(padding + SplitFlapDigit.cardCornerRadius, WidgetGlassBackground.cornerRadius(scale: scale), accuracy: 0.001)
    }

    /// A card flips at full speed when it changes once a second or slower, and
    /// fast enough to finish before the next change when it changes faster —
    /// the stopwatch's hundredths used to be interrupted mid-flip every time.
    func testFlipDurationPacesToHowOftenTheCardChanges() {
        XCTAssertEqual(FlapAnimatingNSView.durationScale(forChangeInterval: 1.0), 1)
        XCTAssertEqual(FlapAnimatingNSView.durationScale(forChangeInterval: .infinity), 1)
        for interval in [0.03, 0.1] {
            let flip = 0.33 * FlapAnimatingNSView.durationScale(forChangeInterval: interval)
            XCTAssertLessThan(flip, interval, "flip must finish before the next change at \(interval)s")
            XCTAssertGreaterThan(flip, interval * 0.5, "but still take most of the gap, so it reads as a flip")
        }
    }

    func testMarginStaysWithinClampAtEverySize() {
        for size in OverlaySize.allCases {
            XCTAssert((11...22).contains(OverlayContentView.padding(scale: size.scale)), "\(size)")
        }
    }
}
