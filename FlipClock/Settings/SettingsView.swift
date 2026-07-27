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
        case .general: return CGSize(width: 430, height: 184)
        case .appearance: return CGSize(width: 470, height: 304)
        case .desktopClock: return CGSize(width: 470, height: 304)
        case .secondClock: return CGSize(width: 470, height: 260)
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
                .padding(.top, 4)
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
        .overlay(alignment: .top) {
            // The window's native title is hidden (see
            // `SettingsWindowController`) — AppKit only centers a titled
            // window's title against a unified `NSToolbar`'s layout guide,
            // and a plain `.fullSizeContentView` window with no toolbar
            // left-aligns it right after the traffic lights instead.
            // Drawing our own centered title directly into that same
            // reserved band (`.ignoresSafeArea` lets it render there
            // without pushing the tab row down further) gets both a
            // centered title *and* zero gap under the traffic lights.
            Text(selectedTab.label)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 28)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private var headerBar: some View {
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

            settingsCard("Font") {
                Picker("Font", selection: $settings.widgetFont) {
                    ForEach(WidgetFont.all) { font in
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

                Picker("Color style", selection: $settings.widgetColorStyle) {
                    ForEach(WidgetColorStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show day, date, month, year", isOn: $settings.showDateOnOverlay)
                Toggle("Float across the screen", isOn: $settings.floatAcrossScreen)
                    .disabled(settings.fillScreen)
                Toggle("Fill screen", isOn: $settings.fillScreen)
            }
        case .secondClock:
            settingsCard("Show second clock") {
                Picker("Display", selection: secondClockDisplayBinding) {
                    ForEach(SecondClockDisplay.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
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
                    .disabled(settings.secondClockDisplay == .off)
                }
            }
        }
    }

    private var secondClockDisplayBinding: Binding<SecondClockDisplay> {
        Binding(
            get: { settings.secondClockDisplay },
            set: { settings.secondClockDisplay = $0 }
        )
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

    // `TimeZone.knownTimeZoneIdentifiers` is the full IANA database macOS
    // ships (every zone `NSTimeZone`/`systemsetup -listtimezones` knows
    // about) — sorted here by actual UTC offset (ascending), the order the
    // user asked for, rather than the default alphabetical-by-identifier
    // order which groups zones by region name instead of by time.
    private var sortedIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.sorted { lhs, rhs in
            let lhsOffset = TimeZone(identifier: lhs)?.secondsFromGMT() ?? 0
            let rhsOffset = TimeZone(identifier: rhs)?.secondsFromGMT() ?? 0
            if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
            return lhs < rhs
        }
    }

    private var timezones: [String] {
        guard !filterText.isEmpty else { return sortedIdentifiers }
        return sortedIdentifiers.filter {
            $0.localizedCaseInsensitiveContains(filterText)
        }
    }

    private func offsetLabel(for identifier: String) -> String {
        guard let seconds = TimeZone(identifier: identifier)?.secondsFromGMT() else { return "" }
        let hours = seconds / 3600
        let minutes = abs(seconds / 60) % 60
        return String(format: "UTC%+03d:%02d", hours, minutes)
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
                    HStack {
                        Text(zone)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(offsetLabel(for: zone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
