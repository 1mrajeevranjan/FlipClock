import SwiftUI

/// The digit-font menu. SwiftUI's `.menu` picker draws every item in the system
/// font on macOS, so the list couldn't be judged by eye — this names each font
/// in its own face, and reports whichever item is highlighted (mouse or arrow
/// keys) so the clock preview can show a font before it's chosen.
struct FontPopUpPicker: NSViewRepresentable {
    @Binding var selection: WidgetFont
    /// The highlighted font while the menu is open; `nil` once it closes or
    /// the pointer leaves it.
    let onHighlight: (WidgetFont?) -> Void

    static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for font in WidgetFont.all {
            let item = NSMenuItem(title: font.label, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: font.label, attributes: [.font: menuFace(for: font)])
            item.representedObject = font.id
            menu.addItem(item)
        }
        return menu
    }

    /// Decorative faces differ wildly at one point size (some read half as
    /// tall), so each is sized to the system menu font's cap height.
    private static func menuFace(for font: WidgetFont) -> NSFont {
        let system = NSFont.menuFont(ofSize: 0)
        guard let name = font.postscriptName, let face = NSFont(name: name, size: system.pointSize),
              face.capHeight > 0 else { return system }
        let size = min(max(system.pointSize * system.capHeight / face.capHeight, 10), 20)
        return NSFont(name: name, size: size) ?? face
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.menu = Self.makeMenu()
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setAccessibilityLabel("Digit font")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if let index = WidgetFont.all.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: FontPopUpPicker

        init(_ parent: FontPopUpPicker) { self.parent = parent }

        @objc func picked(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else { return }
            parent.selection = WidgetFont.byID(id)
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            parent.onHighlight((item?.representedObject as? String).map(WidgetFont.byID))
        }

        /// Deferred: the menu closes before the chosen item's action fires, and
        /// clearing the preview first would flash the old font for a frame.
        func menuDidClose(_ menu: NSMenu) {
            DispatchQueue.main.async { [self] in parent.onHighlight(nil) }
        }
    }
}
