import SwiftUI

struct CountdownTimerView: View {
    @ObservedObject var timerModel: CountdownTimer
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 22) {
            if timerModel.isFinished {
                Image(systemName: "bell.badge")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Time’s up")
                    .font(.title2.weight(.semibold))
                Button("Done") { timerModel.reset() }
                    .popoverActionButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            } else if timerModel.isRunning || timerModel.remainingSeconds > 0 {
                Label(timerModel.isRunning ? "Counting down" : "Paused", systemImage: timerModel.isRunning ? "timer" : "pause.circle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(timerModel.isRunning ? 0.12 : 0.06), in: Capsule())
                FlipTimeDisplay(
                    components: [
                        timerModel.remainingSeconds / 3600,
                        (timerModel.remainingSeconds / 60) % 60,
                        timerModel.remainingSeconds % 60
                    ],
                    isDark: colorScheme == .dark,
                    fontName: settings.widgetFont.postscriptName,
                    cardSize: CGSize(width: 36, height: 56),
                    unitLabels: ["hr", "min", "sec"]
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining")
                .accessibilityValue("\(timerModel.remainingSeconds / 3600) hours, \((timerModel.remainingSeconds / 60) % 60) minutes, \(timerModel.remainingSeconds % 60) seconds")

                HStack(spacing: 12) {
                    Button("Reset") { timerModel.reset() }
                        .popoverActionButton()
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Reset (⌘R)")
                    Button {
                        if timerModel.isRunning { timerModel.pause() } else { timerModel.resume() }
                    } label: {
                        Label(timerModel.isRunning ? "Pause" : "Resume", systemImage: timerModel.isRunning ? "pause.fill" : "play.fill")
                            .frame(minWidth: 78)
                    }
                    .popoverActionButton(prominent: true)
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Pause or resume (Space)")
                }
            } else {
                VStack(spacing: 6) {
                    Text("Set a little time aside")
                        .font(.headline)
                    Text("Scroll a column or use the arrow keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TimeWheelPicker(hours: $timerModel.inputHours, minutes: $timerModel.inputMinutes, seconds: $timerModel.inputSeconds)
                Button { timerModel.start() } label: {
                    Label("Start Timer", systemImage: "play.fill")
                        .frame(minWidth: 100)
                }
                .popoverActionButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(timerModel.inputHours == 0 && timerModel.inputMinutes == 0 && timerModel.inputSeconds == 0)
            }
        }
        .controlSize(.large)
        .tint(.orange)
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(20)
        .modifier(PopoverCardSurface(tint: .orange))
    }
}
