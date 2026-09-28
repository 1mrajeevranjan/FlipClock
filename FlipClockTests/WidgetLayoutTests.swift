import XCTest
@testable import FlipClock

final class WidgetLayoutTests: XCTestCase {
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
