import Foundation

/// Simple count-up stopwatch for the popover — start/stop/reset, elapsed
/// time in whole seconds plus hundredths ("1/100" card — true millisecond
/// resolution would be a third digit and doesn't fit the app's two-digit
/// flip-card convention). Mirrors `CountdownTimer`'s absolute-time
/// approach (track a start reference plus accumulated time, rather than
/// decrementing/incrementing a counter each tick) so a stalled run loop
/// can't drift the displayed time from the real elapsed time.
final class Stopwatch: ObservableObject {
    static let updateInterval: TimeInterval = 0.03
    @Published private(set) var elapsedSeconds: Int = 0
    /// Hundredths of a second (0–99) — ticks every 30ms while running and visible so
    /// the "1/100" flip card visibly updates, unlike `elapsedSeconds` which
    /// only needs a once-a-second cadence.
    @Published private(set) var centiseconds: Int = 0
    @Published private(set) var isRunning: Bool = false

    private var timer: Timer?
    private var startReference: Date?
    private var accumulated: TimeInterval = 0
    private var isDisplayActive = true

    func setDisplayActive(_ active: Bool) {
        guard active != isDisplayActive else { return }
        isDisplayActive = active
        timer?.invalidate()
        timer = nil
        guard isRunning else { return }
        if active {
            tick()
            scheduleTick()
        }
    }

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
        publish(accumulated)
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
        guard isDisplayActive else { return }
        let newTimer = Timer(timeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        guard let startReference else { return }
        let total = accumulated + Date().timeIntervalSince(startReference)
        publish(total)
    }

    private func publish(_ total: TimeInterval) {
        let seconds = Int(total)
        let hundredths = Int((total - total.rounded(.down)) * 100)
        if seconds != elapsedSeconds { elapsedSeconds = seconds }
        if hundredths != centiseconds { centiseconds = hundredths }
    }

    deinit {
        timer?.invalidate()
    }
}
