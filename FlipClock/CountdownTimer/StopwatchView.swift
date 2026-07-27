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

    var body: some View {
        VStack(spacing: 10) {
            Label("Stopwatch", systemImage: "stopwatch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            FlipTimeDisplay(
                components: components,
                isDark: isDark,
                fontName: settings.widgetFont.postscriptName,
                unitLabels: ["hr", "min", "sec", "ms"]
            )

            HStack(spacing: 10) {
                Button(stopwatch.isRunning ? "Stop" : "Start") {
                    if stopwatch.isRunning {
                        stopwatch.stop()
                    } else {
                        stopwatch.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") { stopwatch.reset() }
                    .buttonStyle(.borderless)
                    .disabled(stopwatch.elapsedSeconds == 0 && !stopwatch.isRunning)
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
