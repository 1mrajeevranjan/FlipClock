import Foundation
import AppKit

/// Simple countdown timer for the popover — set minutes/seconds, start,
/// pause/resume, reset. Counts down against an absolute `endDate` rather
/// than decrementing a counter on each tick, so a stalled run loop (the
/// popover closing, the Mac sleeping) can't make the displayed time drift
/// from the real elapsed time. Only a user-started countdown finishing
/// plays its completion sound; tests inject a silent callback.
final class CountdownTimer: ObservableObject {
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isFinished: Bool = false
    @Published var inputHours: Int = 0
    @Published var inputMinutes: Int = 5
    @Published var inputSeconds: Int = 0

    private var timer: Timer?
    private var endDate: Date?
    private var isDisplayActive = true
    private let playCompletionSound: () -> Void

    init(playCompletionSound: @escaping () -> Void = {
        let sound = NSSound(named: "Glass")
        sound?.loops = false
        sound?.play()
    }) {
        self.playCompletionSound = playCompletionSound
    }

    func setDisplayActive(_ active: Bool) {
        guard active != isDisplayActive else { return }
        isDisplayActive = active
        guard isRunning else { return }
        tick()
        if isRunning { scheduleTick() }
    }

    func start() {
        guard !isRunning else { return }
        let total = inputHours * 3600 + inputMinutes * 60 + inputSeconds
        guard total > 0 else { return }
        remainingSeconds = total
        isFinished = false
        resume()
    }

    func resume() {
        guard !isRunning, remainingSeconds > 0 else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        scheduleTick()
    }

    func pause() {
        if let endDate {
            let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            if remaining != remainingSeconds { remainingSeconds = remaining }
        }
        isRunning = false
        timer?.invalidate()
        timer = nil
        endDate = nil
    }

    func reset() {
        pause()
        remainingSeconds = 0
        isFinished = false
    }

    private func scheduleTick() {
        timer?.invalidate()
        guard let endDate else { return }
        let nextTick = endDate.addingTimeInterval(-max(0, ceil(endDate.timeIntervalSinceNow) - 1))
        // Hidden countdowns need a completion alarm, not a once-per-second display tick.
        let newTimer = Timer(fire: isDisplayActive ? nextTick : endDate,
                             interval: isDisplayActive ? 1 : 0, repeats: isDisplayActive) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = Int(ceil(endDate.timeIntervalSinceNow))
        if remaining <= 0 {
            remainingSeconds = 0
            finish()
        } else if remaining != remainingSeconds {
            remainingSeconds = remaining
        }
    }

    private func finish() {
        guard isRunning, !isFinished else { return }
        pause()
        isFinished = true
        playCompletionSound()
    }

    deinit {
        timer?.invalidate()
    }
}
