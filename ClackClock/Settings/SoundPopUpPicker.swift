import SwiftUI

/// The reminder-sound list. A SwiftUI `.menu` picker can't report which item
/// is highlighted, so the only way to hear a sound was to pick it and press
/// the speaker. This plays each sound as the pointer or arrow keys reach it
/// while the list is open, and only chooses one when it's picked.
struct SoundPopUpPicker: NSViewRepresentable {
    @Binding var selection: ReminderSound
    let onPreview: (ReminderSound) -> Void

    static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for sound in ReminderSound.all {
            let item = NSMenuItem(title: sound.label, action: nil, keyEquivalent: "")
            item.representedObject = sound.id
            menu.addItem(item)
        }
        return menu
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.menu = Self.makeMenu()
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setAccessibilityLabel("Notification sound")
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if let index = ReminderSound.all.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: SoundPopUpPicker
        weak var button: NSPopUpButton?
        /// The item the list opened on. macOS highlights it on open, which
        /// isn't the user moving to it, so it stays silent until they leave it.
        private var openedOn: NSMenuItem?

        init(_ parent: SoundPopUpPicker) { self.parent = parent }

        @objc func picked(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else { return }
            parent.selection = ReminderSound.byID(id)
        }

        func menuWillOpen(_ menu: NSMenu) {
            openedOn = button?.selectedItem
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            guard let item else { return }
            if item === openedOn { return }
            openedOn = nil
            guard let id = item.representedObject as? String else { return }
            parent.onPreview(ReminderSound.byID(id))
        }
    }
}
