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

    /// Width is constant across every tab — only height varies with each
    /// tab's content. Varying width too made the centered tab row visibly
    /// slide sideways every time the window resized, which read as the
    /// tabs "jumping" rather than a clean transition.
    static let width: CGFloat = 470

    /// Rough initial estimate used only for the very first layout, before
    /// the real content height has been measured (see
    /// `SettingsView.ContentHeightPreferenceKey`) — the authoritative size
    /// now comes from measuring the actual rendered content, not this
    /// table, so these numbers no longer need to track every content
    /// change exactly.
    var windowSize: CGSize {
        switch self {
        case .general: return CGSize(width: Self.width, height: 184)
        case .appearance: return CGSize(width: Self.width, height: 304)
        case .desktopClock: return CGSize(width: Self.width, height: 336)
        case .secondClock: return CGSize(width: Self.width, height: 260)
        }
    }
}

/// Reports the settings content's real, natural height up to `SettingsView`
/// so the window can be sized to fit it exactly — no scrollbar, no guessed
/// magic numbers per tab that drift out of sync with the actual content.
private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports the title+tab-row+divider overlay's real, natural height —
/// mirrors `ContentHeightPreferenceKey`'s approach for the card body, for
/// the same reason: a hand-computed constant (title 28pt + tab row 50pt)
/// silently went stale the moment a `Divider` was added to that overlay,
/// leaving a visible gap between the divider and the card below since the
/// card's top padding no longer matched the header's real height. Measuring
/// it instead of guessing means it can never drift out of sync again,
/// regardless of what's added to the header block later.
private struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 78
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    private let onChangeWindow: (String, CGSize) -> Void
    @State private var selectedTab: SettingsTab = .general
    @State private var showingTimezonePicker = false
    @State private var measuredHeight: CGFloat = 0
    @State private var pendingResize: DispatchWorkItem?
    @State private var headerHeight: CGFloat = 78
    /// Selection pill's x-offset within the tab row. Animated explicitly via
    /// `withAnimation` (see `headerBar`) rather than through an
    /// `.animation(_:value:)` modifier, so that it — and nothing else — eases.
    @State private var pillX: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onChangeWindow: @escaping (String, CGSize) -> Void = { _, _ in }) {
        self.onChangeWindow = onChangeWindow
    }

    /// Used only for the tab row's own selection highlight sliding between
    /// buttons — `nil` (no animation) when Reduce Motion is on. Content no
    /// longer crossfades (see `content` below), so this has nothing to do
    /// with the window resize animation, which AppKit drives separately.
    ///
    /// Applied via `.animation(_:value:)` scoped to just the highlight fill
    /// below — NOT via `withAnimation` around the `selectedTab` mutation
    /// itself. `withAnimation` puts every view in the transaction into the
    /// same ambient animation, including the title `Text(selectedTab.label)`
    /// overlay: since that text is centered and its intrinsic width changes
    /// with each tab's label length ("General" vs "Second Clock"), the
    /// ambient animation visibly slid the title sideways for ~0.2s on every
    /// switch — read as the tab name "not staying put." Scoping the
    /// animation to only the highlight fill keeps the title an instant,
    /// stable swap while still sliding the pill.
    private var tabTransitionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    var body: some View {
        // `header` and `content` are true `ZStack` siblings, NOT an
        // `.overlay()` riding on `content`. That distinction is the actual
        // fix for a real bug: with `.overlay()`, the header's placement is
        // derived FROM content's resolved frame — an extra dependency hop
        // (window → content → header) that only matters when content's
        // frame is changing *fast and by a lot*, which is exactly what
        // happens on General↔Appearance (the largest content-height delta
        // of any tab pair, since General is by far the shortest tab).
        // Frame-by-frame video analysis (30fps capture of a real switch)
        // caught the smoking gun: on General→Appearance, the tab pill's
        // `matchedGeometryEffect` completely vanished for 2 frames (~66ms)
        // before reappearing mid-slide — a pop, not a slide, which is
        // exactly what "bounces" instead of "slides." The same capture
        // showed Appearance→Desktop Clock (a much smaller height delta)
        // interpolating with zero dropped frames. `.overlay()`'s content-
        // dependent placement recomputing every frame during a large,
        // fast resize was destabilizing `matchedGeometryEffect`'s anchor
        // resolution specifically when that recomputation was big/frequent
        // enough. A `ZStack` positions both children directly off the
        // window's own bounds, in parallel, with no intermediary — content
        // resizing has nothing further to destabilize.
        ZStack(alignment: .top) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
                // Deliberately NOT pinned to `selectedTab.windowSize` here —
                // that forced this content to the *target* size the instant
                // `selectedTab` changed, while `SettingsWindowController`
                // animates the actual NSWindow to that size over ~0.2s
                // separately. The two disagreeing read as a glitch: content
                // snapping to its final layout instantly, then getting
                // clipped/letterboxed by a window that was still mid-resize.
                // Filling whatever the hosting view's *real*, currently
                // animating bounds are keeps content and window in lockstep —
                // window size is driven entirely by the measured height below,
                // not by this frame.
                .padding(.top, headerHeight)
                // Without this, the card body was *also* respecting the
                // system's implicit top safe-area inset reserved for the
                // (visually hidden, but still logically present) title bar —
                // stacking on top of the manual `headerHeight` padding above,
                // which is already accounting for that exact space.
                .ignoresSafeArea(edges: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // The window's native title is hidden (see
            // `SettingsWindowController`) — AppKit only centers a titled
            // window's title against a unified `NSToolbar`'s layout guide,
            // and a plain `.fullSizeContentView` window with no toolbar
            // left-aligns it right after the traffic lights instead.
            // Drawing our own centered title directly into that same
            // reserved band (`.ignoresSafeArea` lets it render there
            // without pushing the tab row down further) gets both a
            // centered title *and* zero gap under the traffic lights.
            VStack(spacing: 0) {
                Text(selectedTab.label)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 28)
                    .allowsHitTesting(false)
                    .animation(nil, value: selectedTab)

                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                // Hairline separating the title/tab row from the card
                // content below.
                Divider()
            }
            // Belt-and-braces companion to the pill's own scoped animation
            // (see `headerBar`): this header block sits at the top of a
            // window whose height AppKit is animating, and any vertical
            // shift it picks up mid-resize must land instantly rather than
            // ease. An eased shift is exactly what was showing up as the
            // pill "bouncing" on General↔Appearance — measured at 60fps as
            // a 39px vertical dip that recovered over the animation's full
            // 200ms. Modifiers closer to the leaf win, so the pill's own
            // `.animation(tabTransitionAnimation, ...)` still drives its
            // horizontal slide; this only suppresses easing on the
            // container's layout.
            .animation(nil, value: selectedTab)
            .ignoresSafeArea(edges: .top)
            // Measured *after* `.ignoresSafeArea`, not before — that
            // modifier grows this block's rendered footprint to bleed
            // into the top safe-area inset (so the title sits flush
            // under the traffic lights, no gap), and a `GeometryReader`
            // placed before it reports the pre-inset size, which is
            // ~28pt too small. Since the goal is reserving exactly as
            // much space in the card below as this header visually
            // occupies on screen, measuring the final, post-inset
            // size is the correct one to use.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeaderHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear { onChangeWindow(selectedTab.label, selectedTab.windowSize) }
        // Updates the window title immediately (it shouldn't lag
        // behind the click) using `tab.windowSize` — the per-tab
        // estimate table — as this tab's best guess, NOT the previous
        // tab's `measuredHeight`: that was a real bug (a different
        // tab's actual content height is not a useful guess for this
        // one) that made the window visibly resize to the wrong
        // height for a beat before the debounced real measurement
        // corrected it a moment later — two resizes, the first one
        // wrong, reading as a stutter. Setting `measuredHeight` to
        // this same guess here means that if the real measurement
        // (arriving via the preference below) turns out to match it —
        // the common case, since the table was tuned against real
        // content — the 0.5pt-delta guard suppresses a redundant
        // second resize entirely.
        .onChange(of: selectedTab) { _, tab in
            measuredHeight = tab.windowSize.height
            onChangeWindow(tab.label, tab.windowSize)
        }
        .onPreferenceChange(ContentHeightPreferenceKey.self) { cardHeight in
            let totalHeight = cardHeight + headerHeight
            guard cardHeight > 0, abs(totalHeight - measuredHeight) > 0.5 else { return }
            // Debounced: a tab switch (and even normal layout passes,
            // e.g. a `Picker` settling its own intrinsic size) can
            // report a couple of slightly-different heights across
            // consecutive frames before settling. Resizing the window
            // on every one of those fired off overlapping/interrupting
            // `NSAnimationContext` animations — each new one canceling
            // the last mid-flight — which is what actually read as
            // "glitchy": not the animation curve itself, but multiple
            // competing animations racing each other. Only the height
            // that's still current after a short quiet period gets
            // applied, so exactly one clean resize happens per switch.
            pendingResize?.cancel()
            let label = selectedTab.label
            let work = DispatchWorkItem {
                measuredHeight = totalHeight
                onChangeWindow(label, CGSize(width: SettingsTab.width, height: totalHeight))
            }
            pendingResize = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { headerHeight = $0 }
        .sheet(isPresented: $showingTimezonePicker) {
            TimezonePickerView(selection: $settings.secondTimezoneID)
                .frame(width: 460, height: 520)
        }
    }

    /// No `ScrollView` — the window is sized to fit this content exactly
    /// (see `ContentHeightPreferenceKey` above), so there's never overflow
    /// to scroll. A `ScrollView` here would also break the height
    /// measurement: it reports its *own* size, not its content's natural
    /// height.
    ///
    /// No crossfade on `selectedTabContent` either, deliberately — an
    /// `.id(selectedTab)` + `.transition(.opacity)` here previously meant
    /// this exact subtree (the one `GeometryReader` measures above) briefly
    /// held *both* the outgoing and incoming tab's content mid-fade, so the
    /// measured height wobbled across several frames of the transition
    /// instead of changing once. Each wobble fired its own window-resize
    /// animation, and those competing resizes were the actual glitch — not
    /// the resize curve itself. A clean instant swap, with the window
    /// resize alone providing the sense of motion, reads far smoother.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectedTabContent
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fixed geometry for the tab row. The pill's position is derived
    /// arithmetically from these (see `headerBar`), so they must stay in
    /// sync with the button `.frame(width:height:)` below.
    private static let tabWidth: CGFloat = 96
    private static let tabHeight: CGFloat = 40
    private static let tabSpacing: CGFloat = 2

    /// Left edge of the selection pill, measured from the tab row's own
    /// leading edge — pure arithmetic from the tab's index, with no
    /// dependency on the layout system whatsoever.
    private static func pillOffset(for tab: SettingsTab) -> CGFloat {
        let index = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        return CGFloat(index) * (tabWidth + tabSpacing)
    }

    private var headerBar: some View {
        HStack(spacing: Self.tabSpacing) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    // `selectedTab` is assigned OUTSIDE the animation
                    // transaction and only `pillX` inside it. That split is
                    // the entire fix — see the pill's `.offset` below.
                    selectedTab = tab
                    let target = Self.pillOffset(for: tab)
                    if let animation = tabTransitionAnimation {
                        withAnimation(animation) { pillX = target }
                    } else {
                        pillX = target
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                        Text(tab.label)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(width: Self.tabWidth, height: Self.tabHeight)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(selectedTab == tab ? .white : .primary)
            }
        }
        // ONE pill for the whole row, positioned by an explicit `.offset`
        // read from `pillX` — a plain `@State` number driven by
        // `withAnimation` in the button action above. Deliberately NOT a
        // per-button background, NOT `matchedGeometryEffect`, and NOT an
        // `.animation(_:value:)` modifier on this view. Each of those was
        // tried and each produced the reported "bounces on General→
        // Appearance, slides cleanly everywhere else" asymmetry:
        //
        //  • Per-button backgrounds: four rectangles independently
        //    cross-fading their fill, so two tinted shapes visibly
        //    co-existed mid-switch.
        //  • `matchedGeometryEffect`: resolves its source/target frames
        //    through the layout system, so a transient re-layout skewed the
        //    interpolation (measured: the pill vanished for 2 frames, then
        //    popped in mid-slide).
        //  • `.animation(_:value:)` on the pill: that modifier animates
        //    EVERY animatable change in its subtree, including position
        //    changes that come from layout rather than from the offset. A
        //    transient layout re-resolution therefore got eased into a
        //    diagonal arc — measured at 60fps as the pill's top edge
        //    dipping 64→103px and recovering over the full 200ms, with its
        //    height squashing 79→46px on the way. Frame captures show it
        //    travelling down-and-right, then arcing back up. That arc is
        //    exactly what reads as a bounce.
        //
        // Assigning `selectedTab` outside the transaction and only `pillX`
        // inside it means the animation applies to a single scalar and
        // nothing else. The pill's own layout position is not animatable
        // here (no `.animation` modifier is attached), so any layout change
        // lands instantly and invisibly, while `pillX` — pure arithmetic,
        // horizontal only — is the sole thing that eases. Every tab pair
        // now runs the identical single-value interpolation.
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor)
                .frame(width: Self.tabWidth, height: Self.tabHeight)
                .offset(x: pillX)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { pillX = Self.pillOffset(for: selectedTab) }
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

                // Without this the picker looks broken while macOS is set to
                // Monochrome: "Full Color" is selected and nothing happens,
                // because the system style is deliberately allowed to win so
                // the widget tracks the native ones beside it.
                if settings.systemWidgetDimming.drainsColor, settings.widgetColorStyle == .full {
                    Text("macOS is dimming desktop widgets, so this widget follows it. Change it in System Settings › Desktop & Dock › “Dim widgets on desktop”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

    // Plain `VStack` + background instead of `GroupBox` — `GroupBox` (even
    // under a fully custom `GroupBoxStyle`) retains hidden internal
    // label-to-content padding on macOS that a style's `makeBody` can't
    // strip out, which is what was leaving a large, unexplained gap
    // between the tab row's divider and the first card's label no matter
    // how tightly the style itself was configured. This card shape (bold
    // label directly above a rounded, tinted content box) still matches
    // the standard macOS settings-pane look — it's just built directly
    // instead of going through `GroupBox`, giving exact control over the
    // label-to-box gap: 8pt, HIG Rule 9.6's spacing unit for related
    // elements.
    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
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
