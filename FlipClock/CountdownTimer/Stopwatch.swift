import Foundation

/// Simple count-up stopwatch for the popover — start/stop/reset, elapsed
/// time in whole seconds plus hundredths ("ms" card — true millisecond
/// resolution would be a third digit and doesn't fit the app's two-digit
/// flip-card convention). Mirrors `CountdownTimer`'s absolute-time
/// approach (track a start reference plus accumulated time, rather than
/// decrementing/incrementing a counter each tick) so a stalled run loop
/// can't drift the displayed time from the real elapsed time.
final class Stopwatch: ObservableObject {
    @Published private(set) var elapsedSeconds: Int = 0
    /// Hundredths of a second (0–99) — ticks every 30ms while running so
    /// the "ms" flip card visibly updates, unlike `elapsedSeconds` which
    /// only needs a once-a-second cadence.
    @Published private(set) var centiseconds: Int = 0
    @Published private(set) var isRunning: Bool = false

    private var timer: Timer?
    private var startReference: Date?
    private var accumulated: TimeInterval = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startReference = Date()
        scheduleTick()
    }

    func stop() {
        guard isRunning else { return }
        if let startReference {
            accumulated += Date().timeIntervalSince(startReference)
        }
        isRunning = false
        startReference = nil
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stop()
        accumulated = 0
        elapsedSeconds = 0
        centiseconds = 0
    }

    private func scheduleTick() {
        let newTimer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        guard let startReference else { return }
        let total = accumulated + Date().timeIntervalSince(startReference)
        elapsedSeconds = Int(total)
        centiseconds = Int((total - total.rounded(.down)) * 100)
    }
}
