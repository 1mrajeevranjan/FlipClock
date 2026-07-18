import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, desktopClock, secondClock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .desktopClock: return "Desktop Clock"
        case .secondClock: return "Second Clock"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Launch, visibility"
        case .appearance: return "Theme and glass"
        case .desktopClock: return "Overlay layout"
        case .secondClock: return "Extra clock"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .desktopClock: return "rectangle.on.rectangle"
        case .secondClock: return "globe"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .general: return CGSize(width: 430, height: 220)
        case .appearance: return CGSize(width: 470, height: 420)
        case .desktopClock: return CGSize(width: 470, height: 305)
        case .secondClock: return CGSize(width: 470, height: 285)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    private let onChangeWindow: (String, CGSize) -> Void
    @State private var selectedTab: SettingsTab = .general
    @State private var showingTimezonePicker = false

    init(onChangeWindow: @escaping (String, CGSize) -> Void = { _, _ in }) {
        self.onChangeWindow = onChangeWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedTabContent
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: selectedTab.windowSize.width, height: selectedTab.windowSize.height)
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear { onChangeWindow(selectedTab.label, selectedTab.windowSize) }
        .onChange(of: selectedTab) { _, tab in
            onChangeWindow(tab.label, tab.windowSize)
        }
        .sheet(isPresented: $showingTimezonePicker) {
            TimezonePickerView(selection: $settings.secondTimezoneID)
                .frame(width: 460, height: 520)
        }
    }

    private var headerBar: some View {
        VStack(spacing: 6) {
            ZStack {
                Text(selectedTab.label)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 26)

            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                            Text(tab.label)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 96, height: 40)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(selectedTab == tab ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            settingsCard("Startup") {
                Toggle("Show desktop clock", isOn: $settings.showDesktopOverlay)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        case .appearance:
            settingsCard("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Picker("AM/PM style", selection: $settings.meridiemStyle) {
                    ForEach(MeridiemStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingsCard("Glass") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Popover glass effect")
                    HStack(spacing: 10) {
                        Text("Solid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.popoverGlassiness, in: 0...1)
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsCard("Tint") {
                Toggle("Use custom tint", isOn: $settings.widgetTintEnabled)
                if settings.widgetTintEnabled {
                    ColorPicker("Tint color", selection: $settings.widgetTintColor)
                }
            }

            settingsCard("Font") {
                Picker("Font", selection: $settings.widgetFont) {
                    ForEach(WidgetFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
                .pickerStyle(.menu)
            }
        case .desktopClock:
            settingsCard("Display") {
                Picker("Size", selection: $settings.overlaySize) {
                    ForEach(OverlaySize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Time format", selection: $settings.timeFormat) {
                    ForEach(TimeFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show day, date, month, year", isOn: $settings.showDateOnOverlay)
                Toggle("Float across the screen", isOn: $settings.floatAcrossScreen)
                    .disabled(settings.fillScreen)
                Toggle("Fill screen", isOn: $settings.fillScreen)
            }
        case .secondClock:
            settingsCard("Menu bar clock") {
                Toggle("Enable second clock", isOn: $settings.showSecondClock)
            }

            settingsCard("Timezone") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.secondTimezoneID)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Choose Timezone") {
                        showingTimezonePicker = true
                    }
                    .disabled(!settings.showSecondClock)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct TimezonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var filterText = ""

    private var timezones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !filterText.isEmpty else { return all }
        return all.filter {
            $0.localizedCaseInsensitiveContains(filterText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search time zone", text: $filterText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            List(selection: $selection) {
                ForEach(timezones, id: \.self) { zone in
                    Text(zone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(zone)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }
}
