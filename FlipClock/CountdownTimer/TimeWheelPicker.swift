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

    private let rowHeight: CGFloat = 32

    var body: some View {
        ZStack {
            // One continuous highlighted band behind all three reels'
            // center row, matching the reference's single pill spanning
            // "0 hours 27 min 0 sec" rather than a separate pill per reel.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(height: rowHeight)

            HStack(spacing: 0) {
                WheelColumn(value: $hours, range: 0...23, unitLabel: "hours", rowHeight: rowHeight, becomesInitialResponder: false)
                WheelColumn(value: $minutes, range: 0...59, unitLabel: "min", rowHeight: rowHeight, becomesInitialResponder: true)
                WheelColumn(value: $seconds, range: 0...59, unitLabel: "sec", rowHeight: rowHeight, becomesInitialResponder: false)
            }
        }
        .frame(height: rowHeight * 5)
        .clipped()
    }
}

/// One scrolling reel of integers over `range` — clamped, not wrapping:
/// it stops dead at `range.lowerBound` and `range.upperBound` rather than
/// cycling past either end (a timer's hour reel stopping at 0 and 23, not
/// spinning back around, matches how a bounded duration picker should
/// behave — unlike a live clock face, which has no real "end"). Renders
/// the center (selected) value plus two fading rows above and below,
/// leaving blank space for rows that would fall outside `range`; input
/// comes entirely from an invisible `NSView` overlay (`WheelScrollCapture`)
/// that captures trackpad scroll deltas and up/down-arrow key presses —
/// SwiftUI has no cross-platform primitive for either on macOS.
private struct WheelColumn: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unitLabel: String
    let rowHeight: CGFloat
    /// Only one reel should grab first-responder on first appearance
    /// (there's no visible focus ring to show which one is "active", so
    /// defaulting to minutes — the most commonly adjusted field — avoids
    /// arrow-key input silently going nowhere until the user clicks a reel).
    let becomesInitialResponder: Bool

    @State private var scrollAccumulator: CGFloat = 0

    private func clamped(_ raw: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, raw))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(-2...2, id: \.self) { rowOffset in
                    row(for: rowOffset)
                        .frame(height: rowHeight)
                }
            }
            .allowsHitTesting(false)

            WheelScrollCapture(
                becomesInitialResponder: becomesInitialResponder,
                onScroll: { deltaY in handleScroll(deltaY) },
                onStep: { direction in value = clamped(value + direction) }
            )
        }
        .frame(height: rowHeight * 5)
    }

    private func row(for rowOffset: Int) -> some View {
        let rawValue = value + rowOffset
        let isCenter = rowOffset == 0
        return HStack(spacing: 4) {
            if range.contains(rawValue) {
                Text("\(rawValue)")
                    .font(.system(size: isCenter ? 20 : 15, weight: isCenter ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                if isCenter {
                    Text(unitLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(isCenter ? 1 : (abs(rowOffset) == 1 ? 0.45 : 0.18))
        .frame(maxWidth: .infinity)
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
        while scrollAccumulator >= rowHeight {
            scrollAccumulator -= rowHeight
            guard value < range.upperBound else { scrollAccumulator = 0; break }
            value += 1
        }
        while scrollAccumulator <= -rowHeight {
            scrollAccumulator += rowHeight
            guard value > range.lowerBound else { scrollAccumulator = 0; break }
            value -= 1
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

    func makeNSView(context: Context) -> WheelScrollCaptureView {
        let view = WheelScrollCaptureView()
        view.onScroll = onScroll
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: WheelScrollCaptureView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onStep = onStep
        if becomesInitialResponder, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class WheelScrollCaptureView: NSView {
    var onScroll: (CGFloat) -> Void = { _ in }
    var onStep: (Int) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

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
