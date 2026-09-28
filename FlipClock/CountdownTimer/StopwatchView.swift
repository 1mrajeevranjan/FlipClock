import SwiftUI

/// Stopwatch control shown in the popover's Stopwatch tab — same
/// flip-card display and centered layout as `CountdownTimerView`, in the
/// user's selected font, counting up instead of down.
struct StopwatchView: View {
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var components: [Int] {
        let hours = stopwatch.elapsedSeconds / 3600
        let minutes = (stopwatch.elapsedSeconds / 60) % 60
        let seconds = stopwatch.elapsedSeconds % 60
        return [hours, minutes, seconds, stopwatch.centiseconds]
    }

    private var hasElapsed: Bool { stopwatch.elapsedSeconds > 0 || stopwatch.centiseconds > 0 }

    var body: some View {
        // No "Stopwatch" heading: the selected tab already says it.
        VStack(spacing: 12) {
            FlipTimeDisplay(
                components: components,
                isDark: isDark,
                fontName: settings.widgetFont.postscriptName,
                unitLabels: ["hr", "min", "sec", "ms"]
            )

            HStack(spacing: 8) {
                Button(stopwatch.isRunning ? "Stop" : "Start") {
                    if stopwatch.isRunning {
                        stopwatch.stop()
                    } else {
                        stopwatch.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                // Space is the conventional start/stop key for a stopwatch.
                .keyboardShortcut(.space, modifiers: [])
                .help("Start or stop (Space)")

                Button("Reset") { stopwatch.reset() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Reset (⌘R)")
                    // Stopped part-way through the first second still has
                    // something to reset — the old check looked at whole
                    // seconds only.
                    .disabled(!hasElapsed && !stopwatch.isRunning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
