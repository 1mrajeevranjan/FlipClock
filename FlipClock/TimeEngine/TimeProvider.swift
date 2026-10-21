import Foundation
import AppKit
import Observation

/// Single shared source of truth for the current time. One instance is
/// injected into every render surface (menu bar, popover, desktop overlay) —
/// never instantiate more than one, or surfaces will drift relative to
/// each other and burn extra CPU on duplicate timers.
@Observable
final class TimeProvider {
    private(set) var tick: ClockTick
    private(set) var delta: DigitDelta

    private var timer: Timer?

    init() {
        let now = ClockTick.now()
        tick = now
        delta = DigitDelta.diff(from: nil, to: now)
        start()
        observeWake()
    }

    private func start() {
        timer?.invalidate()
        // Anchored to the next whole second (a repeating timer keeps that phase), so
        // the seconds flip when the real second does rather than up to 1s later.
        let nextSecond = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down) + 1)
        let t = Timer(fire: nextSecond, interval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // .common run loop mode: a default-mode timer stalls while a status
        // bar menu/popover is tracking, which would visibly freeze the clock.
        // Lets macOS coalesce this wakeup with others; 50ms can't be seen on
        // a seconds display.
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        // Timers can misbehave across long sleep intervals; recreate rather
        // than trust the existing one, and snap straight to the correct
        // time instead of animating through the skipped seconds.
        start()
        refresh()
    }

    private func refresh() {
        let now = ClockTick.now()
        delta = DigitDelta.diff(from: tick, to: now)
        tick = now
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
