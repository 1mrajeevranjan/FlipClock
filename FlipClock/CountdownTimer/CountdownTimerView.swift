import SwiftUI

/// Compact countdown timer control shown in the popover — idle state
/// offers minute/second steppers and a Start button; running/paused state
/// shows the remaining time as MM:SS with Pause/Resume and Reset.
struct CountdownTimerView: View {
    @ObservedObject var timerModel: CountdownTimer

    private var display: String {
        let minutes = timerModel.remainingSeconds / 60
        let seconds = timerModel.remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if timerModel.isFinished {
                HStack {
                    Text("Time's up!")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { timerModel.reset() }
                        .buttonStyle(.borderless)
                }
            } else if timerModel.isRunning || timerModel.remainingSeconds > 0 {
                HStack {
                    Text(display)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Spacer()
                    Button(timerModel.isRunning ? "Pause" : "Resume") {
                        if timerModel.isRunning {
                            timerModel.pause()
                        } else {
                            timerModel.resume()
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Reset") { timerModel.reset() }
                        .buttonStyle(.borderless)
                }
            } else {
                HStack(spacing: 8) {
                    Stepper("\(timerModel.inputMinutes)m", value: $timerModel.inputMinutes, in: 0...180)
                    Stepper("\(timerModel.inputSeconds)s", value: $timerModel.inputSeconds, in: 0...59, step: 5)
                    Spacer()
                    Button("Start") { timerModel.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(timerModel.inputMinutes == 0 && timerModel.inputSeconds == 0)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
