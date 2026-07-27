import Foundation
import AppKit

/// Simple countdown timer for the popover — set minutes/seconds, start,
/// pause/resume, reset. Counts down against an absolute `endDate` rather
/// than decrementing a counter on each tick, so a stalled run loop (the
/// popover closing, the Mac sleeping) can't make the displayed time drift
/// from the real elapsed time. Finishes with a system sound rather than a
/// `UserNotifications` alert — that framework needs the app registered
/// with notification center (entitlements/signing this ad-hoc dev build
/// doesn't have), and a countdown finishing while the popover is open
/// doesn't need a system notification anyway.
final class CountdownTimer: ObservableObject {
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isFinished: Bool = false
    @Published var inputHours: Int = 0
    @Published var inputMinutes: Int = 5
    @Published var inputSeconds: Int = 0

    private var timer: Timer?
    private var endDate: Date?

    func start() {
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
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
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
        } else {
            remainingSeconds = remaining
        }
    }

    private func finish() {
        pause()
        isFinished = true
        NSSound(named: "Glass")?.play()
    }
}
