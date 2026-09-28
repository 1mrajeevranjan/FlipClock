import SwiftUI

/// Settings for one world clock, laid out like the other settings cards (bold
/// title above a tinted box) but kept to two rows so all five clocks fit the
/// window without scrolling.
struct WorldClockCard: View {
    @Binding var clock: WorldClock
    let onPickTimezone: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(WorldClock.offsetLabel(for: clock.timeZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this clock")
                .accessibilityLabel("Remove \(clock.displayName) clock")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: onPickTimezone) {
                        Label(clock.timezoneID, systemImage: "globe")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help("Choose time zone")
                    Spacer(minLength: 8)
                    TextField(WorldClock.cityName(for: clock.timezoneID), text: $clock.customLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .help("Name shown in the menu bar and on the widget — leave empty to use the city")
                        .accessibilityLabel("Clock name")
                }

                HStack(spacing: 12) {
                    Picker("Show in", selection: $clock.display) {
                        ForEach(WorldClockDisplay.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .fixedSize()

                    Picker("Size", selection: $clock.widgetSize) {
                        ForEach(OverlaySize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .fixedSize()
                    .disabled(!clock.showsAsWidget)
                    .help(clock.showsAsWidget ? "Widget size" : "Show this clock as a widget to size it")

                    Spacer(minLength: 0)

                    Picker("Format", selection: $clock.timeFormat) {
                        ForEach(TimeFormat.allCases) { format in
                            Text(format == .twelveHour ? "12h" : "24h").tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Time format")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}
