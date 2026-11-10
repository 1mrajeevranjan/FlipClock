import AppKit
import Combine
import SwiftUI

/// FlipClock's own alert for a ringing reminder, styled after a macOS
/// notification banner and on screen the instant the alarm starts. The
/// native notification can't promise that: usernoted held every banner on
/// this Mac back ~10s in its Apple Intelligence step (see CLAUDE.md), so the
/// native alert is withdrawn just before it's due
/// (`ReminderNotifications.handoverLead`). The panel never activates the app,
/// so it doesn't take focus from whatever is in front.
@MainActor
final class ReminderBannerController {
    private static let margin: CGFloat = 12

    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: ReminderBannerStack(reminders: [], onDismiss: { _ in }, onSilence: {}))
    private let notifications: ReminderNotifications
    private let store: ReminderStore
    private var cancellables = Set<AnyCancellable>()

    init(notifications: ReminderNotifications, store: ReminderStore) {
        self.notifications = notifications
        self.store = store
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Above app windows like a real banner, below menus.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting

        notifications.$ringingIDs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in self?.show(ids) }
            .store(in: &cancellables)
    }

    private func show(_ ids: Set<UUID>) {
        let reminders = store.reminders.filter { ids.contains($0.id) }.sorted { $0.date < $1.date }
        guard !reminders.isEmpty, let screen = NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        hosting.rootView = ReminderBannerStack(
            reminders: reminders,
            onDismiss: { [weak self] reminder in
                self?.notifications.handleResponse(actionIdentifier: ReminderNotifications.dismissActionIdentifier,
                                                   requestIdentifier: ReminderNotifications.identifier(for: reminder.id))
            },
            onSilence: { [weak self] in self?.notifications.stopAlarm() }
        )
        let size = hosting.fittingSize
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - size.width - Self.margin, y: area.maxY - size.height - Self.margin,
                           width: size.width, height: size.height)
        guard !panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 24, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "Reminder: " + reminders.map(\.title).joined(separator: ", "),
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }
}

struct ReminderBannerStack: View {
    let reminders: [Reminder]
    let onDismiss: (Reminder) -> Void
    let onSilence: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(reminders) { reminder in
                ReminderBannerCard(reminder: reminder, onDismiss: { onDismiss(reminder) }, onSilence: onSilence)
            }
        }
        .fixedSize()
    }
}

/// Matches the native alert layout: app icon, bold title and a secondary
/// line, with the Dismiss action in its own column on the right. Clicking the
/// body only silences the alarm, as it does on the native alert.
private struct ReminderBannerCard: View {
    private static let cornerRadius: CGFloat = 16

    let reminder: Reminder
    let onDismiss: () -> Void
    let onSilence: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSilence) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(3)
                        Text("Reminder · \(reminder.date.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(reminder.title), reminder")
            .accessibilityHint("Silences the alarm")

            Divider()

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 84)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel("Dismiss \(reminder.title)")
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBlur(cornerRadius: Self.cornerRadius, material: .popover))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
