import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, desktopClock, worldClocks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .desktopClock: return "Desktop Clock"
        case .worldClocks: return "World Clocks"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .desktopClock: return "macwindow"
        case .worldClocks: return "globe"
        }
    }
}

struct SettingsView: View {
    static let minimumWidth: CGFloat = 700
    let onContentHeightChange: (CGFloat) -> Void
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var reminderNotifications: ReminderNotifications
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .general
    @State private var pickingTimezoneFor: WorldClock.ID?
    @State private var addingClock = false

    init(reminderNotifications: ReminderNotifications, onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.reminderNotifications = reminderNotifications
        self.onContentHeightChange = onContentHeightChange
    }

    // ponytail: a still preview shares the clock renderer without another ticking timer.
    private static let previewTick = ClockTick(
        date: Date(), hour12: 10, hour24: 10, minute: 9, second: 30, isPM: false
    )

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                    SettingsNavigationCard(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .help("\(tab.label) (⌘\(index + 1))")
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
            .frame(width: 196)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    selectedTabContent
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: Self.minimumWidth, minHeight: 220)
        .background(Color(nsColor: .windowBackgroundColor))
        .onPreferenceChange(SettingsContentHeightKey.self, perform: onContentHeightChange)
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear { reminderNotifications.refresh() }
        .sheet(isPresented: Binding(
            get: { pickingTimezoneFor != nil || addingClock },
            set: { if !$0 { pickingTimezoneFor = nil; addingClock = false } }
        )) {
            if addingClock {
                TimezonePickerView(selection: Binding(
                    get: { TimeZone.current.identifier },
                    set: { settings.addWorldClock(timezoneID: $0) }
                ))
                .frame(width: 480, height: 540)
            } else if let id = pickingTimezoneFor, let binding = worldClockBinding(id) {
                TimezonePickerView(selection: binding.timezoneID)
                    .frame(width: 480, height: 540)
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            clockPreview
            settingsCard {
                SettingsRow("Desktop clock", detail: "Keep the time visible on your wallpaper.") {
                    Toggle("Desktop clock", isOn: $settings.showDesktopOverlay).fixedSize()
                }
                Divider()
                SettingsRow("Launch at login", detail: "Ready whenever you start your Mac.") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin).fixedSize()
                }
            }
            settingsCard("Reminders") {
                SettingsRow("Notifications", detail: reminderNotifications.statusMessage) {
                    if reminderNotifications.authorizationStatus == .notDetermined {
                        Button("Enable Notifications") { reminderNotifications.enable() }
                            .disabled(reminderNotifications.isRequestingPermission)
                    } else if reminderNotifications.needsSystemSettings {
                        Button("Open Settings…") { reminderNotifications.openSystemSettings() }
                    } else {
                        Text("Allowed")
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                SettingsRow("Notification sound") {
                    HStack(spacing: 8) {
                        Picker("Notification sound", selection: $settings.reminderSound) {
                            ForEach(ReminderSound.all) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Button { reminderNotifications.playPreview(settings.reminderSound) } label: {
                            Image(systemName: "speaker.wave.2.fill").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.reminderSound == .systemDefault)
                        .help("Preview notification sound")
                        .accessibilityLabel("Preview notification sound")
                    }
                }
                if let error = reminderNotifications.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label("Click the menu bar clock for your calendar, timer and stopwatch.", systemImage: "cursorarrow.click")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .appearance:
            clockPreview
            settingsCard {
                SettingsRow("Appearance") {
                    Picker("Appearance", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow("AM/PM style") {
                    Picker("AM/PM style", selection: $settings.meridiemStyle) {
                        ForEach(MeridiemStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow("Digit font") {
                    Picker("Digit font", selection: $settings.widgetFont) {
                        ForEach(WidgetFont.all) { font in
                            Text(font.label)
                                .font(font.postscriptName.map { .custom($0, size: 14) } ?? .system(size: 14))
                                .tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

        case .desktopClock:
            clockPreview
            settingsCard("Layout") {
                SettingsRow("Size") {
                    Picker("Size", selection: $settings.overlaySize) {
                        ForEach(OverlaySize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow("Time format") {
                    Picker("Time format", selection: $settings.timeFormat) {
                        ForEach(TimeFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow("Show date") {
                    Toggle("Show date", isOn: $settings.showDateOnOverlay).fixedSize()
                }
            }
            settingsCard("Behaviour") {
                SettingsRow("Colour style") {
                    Picker("Colour style", selection: $settings.widgetColorStyle) {
                        ForEach(WidgetColorStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if settings.systemWidgetDimming != .never {
                    Text(settings.systemWidgetDimming == .always
                         ? "Always dimmed to match macOS. Change this in System Settings › Desktop & Dock › Dim widgets on desktop."
                         : "Dims when an app is in front, just like macOS widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                SettingsRow("Fill screen") {
                    Toggle("Fill screen", isOn: $settings.fillScreen).fixedSize()
                }
                SettingsRow("Float across screen") {
                    Toggle("Float across screen", isOn: $settings.floatAcrossScreen).fixedSize()
                        .disabled(settings.fillScreen)
                }
                if settings.fillScreen {
                    Text("Turn off Fill screen to let the clock float.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .worldClocks:
            if settings.worldClocks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe.europe.africa")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("A world of time")
                        .font(.title3.weight(.semibold))
                    Text("Add a city to see its time in your menu bar or on your desktop.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            ForEach(settings.worldClocks) { clock in
                if let binding = worldClockBinding(clock.id) {
                    WorldClockCard(clock: binding) {
                        pickingTimezoneFor = clock.id
                    } onRemove: {
                        settings.removeWorldClock(id: clock.id)
                    }
                }
            }
            HStack {
                Text("\(settings.worldClocks.count) of \(WorldClock.maxCount) clocks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addingClock = true
                } label: {
                    Label("Add Clock", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.canAddWorldClock)
            }
        }
    }

    private var clockPreview: some View {
        VStack(spacing: 8) {
            SplitFlapClockFace(
                tick: Self.previewTick, scale: 0.6, showPedestal: false,
                meridiemStyle: settings.meridiemStyle, timeFormat: settings.timeFormat,
                glassCard: true, showOwnGlassPanel: false,
                fontName: settings.widgetFont.postscriptName
            )
            if selectedTab == .desktopClock && settings.showDateOnOverlay {
                DateFlapRow(date: Self.previewTick.date, scale: 0.6,
                            isDark: colorScheme == .dark, glassCard: true,
                            fontName: settings.widgetFont.postscriptName)
            }
            Text("CLOCK PREVIEW")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clock preview, 10:09:30, \(settings.widgetFont.label) font")
    }

    private func settingsCard<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func worldClockBinding(_ id: WorldClock.ID) -> Binding<WorldClock>? {
        guard settings.worldClocks.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { settings.worldClocks.first { $0.id == id } ?? WorldClock(timezoneID: "UTC") },
            set: { newValue in
                guard let index = settings.worldClocks.firstIndex(where: { $0.id == id }) else { return }
                settings.worldClocks[index] = newValue
            }
        )
    }
}

private struct SettingsNavigationCard: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 1 : 0.65),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.35)
                                  : Color.primary.opacity(isHovered ? 0.14 : 0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content.labelsHidden().frame(width: 220, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TimezonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var filterText = ""
    @State private var pendingSelection: String
    @State private var choices: [TimeZoneChoice]
    @FocusState private var searchFocused: Bool

    init(selection: Binding<String>) {
        _selection = selection
        _pendingSelection = State(initialValue: selection.wrappedValue)
        _choices = State(initialValue: TimeZoneChoice.all(including: selection.wrappedValue))
    }

    private var filteredChoices: [TimeZoneChoice] {
        choices.filter { $0.matches(filterText) }
    }

    var body: some View {
        let matches = filteredChoices
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a time zone")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search city or region", text: $filterText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("Search city or region")
                    if !filterText.isEmpty {
                        Button { filterText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)

            Divider()
            ScrollViewReader { proxy in
                List(selection: $pendingSelection) {
                    ForEach(matches) { choice in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(choice.city).fontWeight(.medium)
                                Text(choice.id.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(choice.offsetLabel)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(choice.id)
                        .id(choice.id)
                    }
                }
                .onAppear { proxy.scrollTo(pendingSelection, anchor: .center) }
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: filterText)
                    }
                }
            }
            Divider()
            HStack {
                Text("Sorted by UTC offset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose") {
                    selection = pendingSelection
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .onAppear { searchFocused = true }
    }
}
