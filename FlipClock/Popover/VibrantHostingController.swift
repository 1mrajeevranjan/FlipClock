import SwiftUI
import AppKit
import Combine

/// Hosts SwiftUI content *inside* a real `NSVisualEffectView` root, rather
/// than behind it via SwiftUI's `.background()` modifier. That distinction
/// matters: `.background()` nests the effect view behind other content
/// within one `NSHostingView`, which renders a visibly weaker/flatter
/// blur than NSPopover's own arrow-tip chrome (drawn directly by the
/// popover's frame, not nested inside anything). Making the visual effect
/// view the actual top-level content view — with SwiftUI hosted as its
/// subview — is the structure Apple's own vibrant popover content uses,
/// and is what actually matches the tip's blur exactly.
final class VibrantHostingController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>
    private let material: NSVisualEffectView.Material
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private let scrim = NSView()

    init(rootView: Content, settings: AppSettings, material: NSVisualEffectView.Material = .popover) {
        hostingController = NSHostingController(rootView: rootView)
        self.settings = settings
        self.material = material
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = material
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        view = effectView

        // A solid-color scrim sitting between the blur and the SwiftUI
        // content — dialing its opacity is what "solid to clear glass"
        // means in practice, since NSVisualEffectView itself has no
        // continuous opacity control of its own.
        scrim.wantsLayer = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrim)
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: effectView.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        // NSHostingController's own default background is opaque, which
        // would otherwise sit on top of the scrim and hide it completely
        // regardless of the slider. That's handled by applying
        // `.background(Color.clear)` at the SwiftUI level (see
        // PopoverClockView) rather than poking `hostedView.layer` directly
        // from here — the latter was tried first and broke
        // `.preferredColorScheme` reactivity for this specific view
        // (content froze on its first-render theme and stopped updating),
        // most likely by interfering with NSHostingView's own internal
        // state tracking.
        addChild(hostingController)
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        // Applied directly to the effect view — not to `popover.appearance`
        // — so the frame/arrow (drawn by NSPopover itself) and this nested
        // view resolve vibrancy along the same default path, and only our
        // own content's light/dark actually changes with the setting.
        applyAppearance(to: effectView)
        applyGlassiness()

        settings.$theme
            .sink { [weak self, weak effectView] _ in
                guard let self, let effectView else { return }
                self.applyAppearance(to: effectView)
            }
            .store(in: &cancellables)
        settings.$popoverGlassiness
            .sink { [weak self] _ in self?.applyGlassiness() }
            .store(in: &cancellables)
    }

    private func applyAppearance(to effectView: NSVisualEffectView) {
        switch settings.theme {
        case .light: effectView.appearance = NSAppearance(named: .aqua)
        case .dark: effectView.appearance = NSAppearance(named: .darkAqua)
        case .system: effectView.appearance = nil
        }
    }

    private func applyGlassiness() {
        // "Reduce transparency" (System Settings > Accessibility > Display)
        // is an OS-level accommodation, not just another app preference —
        // it overrides the user's own glassiness slider rather than
        // blending with it, same as `WidgetGlassBackground` does for the
        // desktop overlay.
        let scrimAlpha = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? 1
            : 1 - settings.popoverGlassiness
        scrim.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(scrimAlpha)
            .cgColor
    }

    // NSPopover re-parents its `contentViewController.view` into a fresh
    // backing window on every `show()` — reproduced directly: the first
    // open after changing the theme renders correctly, but closing and
    // reopening the *same* popover again (with no further setting change)
    // reverts to the previous appearance. `settings.theme` never actually
    // changes in that sequence, so the `$theme` sink above never refires
    // to reapply it. Forcing a refresh on every appearance — not just on
    // every settings change — closes that gap regardless of the exact
    // internal reason SwiftUI's `.preferredColorScheme` doesn't
    // reliably re-propagate across the re-parent.
    override func viewWillAppear() {
        super.viewWillAppear()
        if let effectView = view as? NSVisualEffectView {
            applyAppearance(to: effectView)
        }
        applyGlassiness()
        hostingController.rootView = hostingController.rootView
    }

    // NSPopover reads `contentViewController.preferredContentSize`, not
    // the nested hosting controller's — mirror it after each layout pass,
    // by which point SwiftUI's content has settled and `fittingSize` is
    // accurate (unlike querying it synchronously right after construction,
    // before any layout has run).
    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = hostingController.view.fittingSize
        // `scrim.layer` may not exist yet the first time `applyGlassiness`
        // runs in `loadView` (AppKit can defer backing-layer creation
        // until the view actually enters a window) — reapplying here,
        // after every layout pass, guarantees it lands once the layer is
        // real.
        applyGlassiness()
    }
}
