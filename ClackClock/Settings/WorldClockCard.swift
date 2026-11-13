import SwiftUI

struct WorldClockCard: View {
    @Binding var clock: WorldClock
    let onPickTimezone: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.title2.weight(.light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clock.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(WorldClock.offsetLabel(for: clock.timeZone))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Remove this clock")
                .accessibilityLabel("Remove \(clock.displayName) clock")
            }

            SettingsRow("Time zone") {
                Button(action: onPickTimezone) {
                    HStack {
                        Text(clock.timezoneID.replacingOccurrences(of: "_", with: " "))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose time zone")
                .accessibilityLabel("Time zone, \(clock.timezoneID). Choose time zone")
            }

            SettingsRow("Name") {
                TextField("Clock name", text: $clock.customLabel, prompt: Text(WorldClock.cityName(for: clock.timezoneID)))
                    .textFieldStyle(.roundedBorder)
                    .help("Leave empty to use the city name")
            }
            Divider()
            SettingsRow("Show in") {
                Picker("Show in", selection: $clock.display) {
                    ForEach(WorldClockDisplay.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow("Size") {
                Picker("Size", selection: $clock.widgetSize) {
                    ForEach(OverlaySize.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!clock.showsAsWidget)
                .help(clock.showsAsWidget ? "Widget size" : "Show this clock as a widget to size it")
            }
            SettingsRow("Time format") {
                Picker("Time format", selection: $clock.timeFormat) {
                    ForEach(TimeFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
    }
}
