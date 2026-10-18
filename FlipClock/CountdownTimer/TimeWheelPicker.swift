import SwiftUI
import AppKit

/// Three side-by-side scrolling reels (hours/minutes/seconds), matching
/// iOS's Clock app timer picker — replaces the earlier circular "radial
/// dial" attempt, which wasn't actually what was being asked for. Each
/// reel is driven purely by trackpad scroll and the keyboard up/down
/// arrows; deliberately no visible increment/decrement buttons. Each reel
/// is clamped (0–23 hours, 0–59 minutes/seconds), not wrapping past either
/// end — a bounded duration picker, not a live clock face.
struct TimeWheelPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    @State private var focusedUnit: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                WheelColumn(value: $hours, focusedUnit: $focusedUnit, range: 0...23, unitLabel: "hours", becomesInitialResponder: false)
                WheelColumn(value: $minutes, focusedUnit: $focusedUnit, range: 0...59, unitLabel: "min", becomesInitialResponder: true)
                WheelColumn(value: $seconds, focusedUnit: $focusedUnit, range: 0...59, unitLabel: "sec", becomesInitialResponder: false)
            }

            // Glass must own its foreground labels, or the container can blur them as backdrop content.
            HStack(spacing: 0) {
                selectedReel(value: hours, range: 0...23, unit: "hours")
                selectedReel(value: minutes, range: 0...59, unit: "min")
                selectedReel(value: seconds, range: 0...59, unit: "sec")
            }
                .frame(height: TimeWheelReel.selectionHeight)
                .modifier(PopoverControlSurface(tint: .orange.opacity(0.04), cornerRadius: TimeWheelReel.selectionHeight / 2, usesClearGlass: true))
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.06), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: TimeWheelReel.height)
        .clipped()
    }

    private func selectedReel(value: Int, range: ClosedRange<Int>, unit: String) -> some View {
        TimeWheelReel(position: CGFloat(value), range: range, unitLabel: unit,
                      showsUnit: true, isFocused: focusedUnit == unit,
                      viewportHeight: TimeWheelReel.selectionHeight)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: value)
            .clipped()
    }
}

/// One scrolling reel of integers over `range` — clamped, not wrapping:
/// it stops dead at `range.lowerBound` and `range.upperBound` rather than
/// cycling past either end (a timer's hour reel stopping at 0 and 23, not
/// spinning back around, matches how a bounded duration picker should
/// behave — unlike a live clock face, which has no real "end"). Renders
/// fading rows above and below the separately composited selection,
/// leaving blank space for rows that would fall outside `range`; input
/// comes entirely from an invisible `NSView` overlay (`WheelScrollCapture`)
/// that captures trackpad scroll deltas and up/down-arrow key presses —
/// SwiftUI has no cross-platform primitive for either on macOS.
private struct WheelColumn: View {
    @Binding var value: Int
    @Binding var focusedUnit: String?
    let range: ClosedRange<Int>
    let unitLabel: String
    /// Only one reel should grab first-responder on first appearance
    /// (there's no visible focus ring to show which one is "active", so
    /// defaulting to minutes — the most commonly adjusted field — avoids
    /// arrow-key input silently going nowhere until the user clicks a reel).
    let becomesInitialResponder: Bool

    @State private var scrollAccumulator: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func clamped(_ raw: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, raw))
    }

    var body: some View {
        ZStack {
            TimeWheelReel(position: CGFloat(value), range: range, unitLabel: unitLabel,
                          showsUnit: false, isFocused: focusedUnit == unitLabel,
                          viewportHeight: TimeWheelReel.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: value)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    Color.clear.frame(height: TimeWheelReel.selectionHeight)
                    Rectangle()
                }
            }
            .allowsHitTesting(false)

            WheelScrollCapture(
                becomesInitialResponder: becomesInitialResponder,
                onScroll: { deltaY in handleScroll(deltaY) },
                onStep: { direction in value = clamped(value + direction) },
                onFocusChanged: { focused in
                    if focused { focusedUnit = unitLabel }
                    else if focusedUnit == unitLabel { focusedUnit = nil }
                }
            )
            .accessibilityHidden(true)
        }
        .frame(height: TimeWheelReel.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unitLabel)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = clamped(value + 1)
            case .decrement: value = clamped(value - 1)
            @unknown default: break
            }
        }
        .help("Scroll to adjust \(unitLabel), or click and use ↑ / ↓")
    }

    /// Accumulates small scroll deltas until they cross a full row height,
    /// then steps the value by however many rows that crossing covers —
    /// this is what makes a fast trackpad flick move several values at
    /// once instead of capping at one step per scroll event. Stops
    /// accumulating once clamped at either end, so a continued flick past
    /// the boundary doesn't build up a large backlog that then has to
    /// "unwind" before the reel starts moving the other way.
    private func handleScroll(_ deltaY: CGFloat) {
        // NOTE: sign convention assumes "natural" scrolling (swipe up ==
        // content moves up == next/incrementing value scrolls into the
        // center from below), matching the reel visually rotating like the
        // reference. Flip this negation if a real trackpad test shows it
        // running backwards for a given user's scroll-direction setting.
        scrollAccumulator -= deltaY
        while scrollAccumulator >= TimeWheelReel.rowHeight {
            scrollAccumulator -= TimeWheelReel.rowHeight
            guard value < range.upperBound else { scrollAccumulator = 0; break }
            value += 1
        }
        while scrollAccumulator <= -TimeWheelReel.rowHeight {
            scrollAccumulator += TimeWheelReel.rowHeight
            guard value > range.lowerBound else { scrollAccumulator = 0; break }
            value -= 1
        }
    }
}

struct TimeWheelReel: View, Animatable {
    nonisolated static let rowHeight: CGFloat = 32
    nonisolated static let selectionHeight: CGFloat = 44
    nonisolated static let maximumMagnification: CGFloat = 2.55
    nonisolated static let numeralWidth: CGFloat = 54
    nonisolated static let height = rowHeight * 5

    var position: CGFloat
    let range: ClosedRange<Int>
    let unitLabel: String
    let showsUnit: Bool
    let isFocused: Bool
    let viewportHeight: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = min(CGFloat(range.upperBound), max(CGFloat(range.lowerBound), newValue)) }
    }

    nonisolated static func magnification(atRowDistance distance: CGFloat) -> CGFloat {
        let lensRadius = selectionHeight / (2 * rowHeight)
        let normalized = distance / lensRadius
        return 1 + (maximumMagnification - 1) * max(0, 1 - normalized * normalized)
    }

    var body: some View {
        HStack(spacing: 4) {
            TimeWheelNumerals(position: position, range: range, magnified: showsUnit)
            .frame(width: Self.numeralWidth, height: viewportHeight)
            .clipped()
            Text(unitLabel)
                .font(.caption.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                .opacity(showsUnit ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        // Position already interpolates the reel; its individual row offsets must not animate a second time.
        .transaction { $0.animation = nil }
    }
}

private struct TimeWheelNumerals: View {
    let position: CGFloat
    let range: ClosedRange<Int>
    let magnified: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let position = position
        let range = range
        let magnified = magnified
        let ink: Color = colorScheme == .dark ? .white : .black
        let rowHeight = TimeWheelReel.rowHeight
        let pixelHeight = 1 / max(1, displayScale)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let values = max(range.lowerBound, Int(position.rounded(.down)) - 3)...min(range.upperBound, Int(position.rounded(.up)) + 3)
            let rows = values.map { number in
                let distance = CGFloat(number) - position
                let weight: Font.Weight = magnified && TimeWheelReel.magnification(atRowDistance: distance) > 1.12 ? .semibold : .regular
                let text = context.resolve(Text("\(number)")
                    .font(.system(size: 16, weight: weight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink))
                return (text: text, y: center.y + distance * rowHeight,
                        opacity: max(0.28, 1 - abs(distance) * 0.45))
            }

            func drawRows(in graphics: inout GraphicsContext, sourceTop: CGFloat, sourceBottom: CGFloat) {
                for row in rows where row.y + 12 >= sourceTop && row.y - 12 <= sourceBottom {
                    graphics.opacity = row.opacity
                    graphics.draw(row.text, at: CGPoint(x: center.x, y: row.y), anchor: .center)
                }
            }

            guard magnified else {
                drawRows(in: &context, sourceTop: 0, sourceBottom: size.height)
                return
            }

            // Pixel-high affine slices reproduce a convex lens without a filtered layer inside system glass.
            func sourceY(_ destinationY: CGFloat) -> CGFloat {
                let offset = destinationY - center.y
                return center.y + offset / TimeWheelReel.magnification(atRowDistance: offset / rowHeight)
            }

            for top in stride(from: CGFloat.zero, to: size.height, by: pixelHeight) {
                let bottom = min(top + pixelHeight, size.height)
                let sourceTop = sourceY(top), sourceBottom = sourceY(bottom)
                let distance = ((top + bottom) / 2 - center.y) / rowHeight
                let xScale = 1 + 0.8 * (TimeWheelReel.magnification(atRowDistance: distance) - 1)
                var slice = context
                slice.clip(to: Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)))
                slice.translateBy(x: center.x, y: top)
                slice.scaleBy(x: xScale, y: (bottom - top) / (sourceBottom - sourceTop))
                slice.translateBy(x: -center.x, y: -sourceTop)
                drawRows(in: &slice, sourceTop: sourceTop, sourceBottom: sourceBottom)
            }
        }
    }
}

/// Invisible `NSView` overlay that captures trackpad scroll (`scrollWheel`)
/// and up/down arrow keys (`keyDown`) — SwiftUI has no `.onScroll`/arrow-key
/// modifier for an arbitrary view on macOS (only inside `ScrollView`,
/// which brings its own scrollbar and paging behavior we don't want here).
private struct WheelScrollCapture: NSViewRepresentable {
    let becomesInitialResponder: Bool
    let onScroll: (CGFloat) -> Void
    let onStep: (Int) -> Void
    let onFocusChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WheelScrollCaptureView {
        let view = WheelScrollCaptureView()
        view.focusRingType = .none
        view.onScroll = onScroll
        view.onStep = onStep
        view.onFocusChanged = onFocusChanged
        view.requestsInitialFocus = becomesInitialResponder
        return view
    }

    func updateNSView(_ nsView: WheelScrollCaptureView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onStep = onStep
        nsView.onFocusChanged = onFocusChanged
    }
}

final class WheelScrollCaptureView: NSView {
    var onScroll: (CGFloat) -> Void = { _ in }
    var onStep: (Int) -> Void = { _ in }
    var onFocusChanged: (Bool) -> Void = { _ in }
    var requestsInitialFocus = false
    private var didRequestInitialFocus = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, requestsInitialFocus, !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        // Initial focus only: view updates must not steal it from another reel.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        onFocusChanged(accepted)
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChanged(false) }
        return accepted
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll(event.scrollingDeltaY)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onStep(1)   // Up arrow — increase
        case 125: onStep(-1)  // Down arrow — decrease
        default: super.keyDown(with: event)
        }
    }
}
