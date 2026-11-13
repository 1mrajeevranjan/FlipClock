import SwiftUI

struct StopwatchView: View {
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var hasElapsed: Bool { stopwatch.elapsedSeconds > 0 || stopwatch.centiseconds > 0 }

    var body: some View {
        VStack(spacing: 26) {
            Label(stopwatch.isRunning ? "Recording time" : (hasElapsed ? "Paused" : "Ready when you are"),
                  systemImage: stopwatch.isRunning ? "stopwatch" : "stopwatch.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.teal.opacity(stopwatch.isRunning ? 0.12 : 0.06), in: Capsule())

            FlipTimeDisplay(
                components: [stopwatch.elapsedSeconds / 3600, (stopwatch.elapsedSeconds / 60) % 60,
                             stopwatch.elapsedSeconds % 60, stopwatch.centiseconds],
                isDark: colorScheme == .dark,
                fontName: settings.widgetFont.postscriptName,
                // Hundredths use their actual unit, rather than the former misleading “ms”.
                unitLabels: ["hr", "min", "sec", "1/100"],
                lastComponentChangeIntervals: (0.1, Stopwatch.updateInterval)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue("\(stopwatch.elapsedSeconds / 3600) hours, \((stopwatch.elapsedSeconds / 60) % 60) minutes, \(stopwatch.elapsedSeconds % 60) seconds")

            HStack(spacing: 12) {
                Button("Reset") { stopwatch.reset() }
                    .popoverActionButton()
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Reset (⌘R)")
                    .disabled(!hasElapsed && !stopwatch.isRunning)
                Button {
                    if stopwatch.isRunning { stopwatch.stop() } else { stopwatch.start() }
                } label: {
                    Label(stopwatch.isRunning ? "Pause" : (hasElapsed ? "Resume" : "Start"),
                          systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill")
                        .frame(minWidth: 78)
                }
                .popoverActionButton(prominent: true)
                .keyboardShortcut(.space, modifiers: [])
                .help("Start or pause (Space)")
            }
            Text("Space to \(stopwatch.isRunning ? "pause" : "start") · ⌘R to reset")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.large)
        .tint(.teal)
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(20)
        .modifier(PopoverCardSurface(tint: .teal))
    }
}
