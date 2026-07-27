import SwiftUI

/// Countdown timer control shown in the popover's Timer tab — idle state
/// offers a `TimeWheelPicker` (hours/minutes/seconds scrolling reels,
/// trackpad/keyboard driven, no visible arrow buttons) and a Start button;
/// running/paused state shows the remaining time as split-flap cards in
/// the user's selected font, with Pause/Resume and Reset. Everything is
/// centered, same as the clock face on the Calendar tab.
struct CountdownTimerView: View {
    @ObservedObject var timerModel: CountdownTimer
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 10) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if timerModel.isFinished {
                VStack(spacing: 8) {
                    Text("Time's up!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                    Button("Dismiss") { timerModel.reset() }
                        .buttonStyle(.borderless)
                }
            } else if timerModel.isRunning || timerModel.remainingSeconds > 0 {
                VStack(spacing: 10) {
                    FlipTimeDisplay(
                        components: [
                            timerModel.remainingSeconds / 3600,
                            (timerModel.remainingSeconds / 60) % 60,
                            timerModel.remainingSeconds % 60
                        ],
                        isDark: isDark,
                        fontName: settings.widgetFont.postscriptName
                    )
                    HStack(spacing: 10) {
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
                }
            } else {
                VStack(spacing: 10) {
                    TimeWheelPicker(hours: $timerModel.inputHours, minutes: $timerModel.inputMinutes, seconds: $timerModel.inputSeconds)
                    Button("Start") { timerModel.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(timerModel.inputHours == 0 && timerModel.inputMinutes == 0 && timerModel.inputSeconds == 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
