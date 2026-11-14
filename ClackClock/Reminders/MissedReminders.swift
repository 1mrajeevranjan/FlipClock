import QuartzCore
import SwiftUI

/// The bell for reminders that rang while nobody was at the Mac: ringing
/// until the widget or menu bar clock is clicked, then still while any remain.
enum MissedBellState {
    case none, ringing, waiting
}

/// Red bell badge — in the widget's top-right corner and beside the menu bar
/// clock. Swings like a ringing bell, then rests a beat, until clicked.
struct MissedReminderBell: View {
    let isRinging: Bool
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Swing angles, each with how long the swing into it takes; the last
    /// holds still so the ringing reads as bursts, not a constant wobble.
    private static let swings: [(angle: Double, duration: Double)] = [
        (22, 0.09), (-18, 0.1), (14, 0.1), (-10, 0.1), (6, 0.1), (0, 0.1), (0, 0.9)
    ]

    var body: some View {
        let badge = Image(systemName: "bell.fill")
            .font(.system(size: diameter * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.red))
            .shadow(color: .black.opacity(0.25), radius: diameter / 8, y: 1)
        Group {
            if isRinging && !reduceMotion {
                badge.phaseAnimator(Self.swings.indices) { content, index in
                    content.rotationEffect(.degrees(Self.swings[index].angle), anchor: .top)
                } animation: { index in
                    .easeInOut(duration: Self.swings[index].duration)
                }
            } else {
                badge
            }
        }
        .accessibilityLabel("Missed reminder")
    }
}

/// "Team meeting @ 8:00 AM" as one paragraph, so it only wraps when the
/// title is too long for the row.
struct ReminderLine: View {
    let reminder: Reminder
    var now = Date()
    var font: Font = .callout

    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        (Text(reminder.title).fontWeight(.semibold) + Text(" @ \(Self.when(reminder.date, now: now))").foregroundStyle(.secondary))
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What clicking the bouncing widget opens: each missed reminder with a
/// Dismiss button on its right.
struct MissedRemindersView: View {
    let reminders: [Reminder]
    let onDismiss: (Reminder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(reminders.count == 1 ? "Missed Reminder" : "Missed Reminders", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .accessibilityAddTraits(.isHeader)
            ForEach(reminders) { reminder in
                HStack(spacing: 12) {
                    ReminderLine(reminder: reminder, font: .body)
                    Button("Dismiss") { onDismiss(reminder) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Dismiss \(reminder.title)")
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            Text("Rang while your Mac was asleep or locked.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// The menu bar popover's list of missed reminders, styled like its "Due
/// Today" list but with a Dismiss button on each row.
struct MissedReminderBanner: View {
    let reminders: [Reminder]
    let onDismiss: (Reminder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Missed", systemImage: "bell.badge.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityAddTraits(.isHeader)
            ForEach(reminders) { reminder in
                HStack(spacing: 10) {
                    ReminderLine(reminder: reminder)
                    Button("Dismiss") { onDismiss(reminder) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .accessibilityLabel("Dismiss \(reminder.title)")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.18)))
    }
}

/// The menu bar clock's hop. Done in SwiftUI rather than on the layer: the
/// status bar button is a flipped view, so a layer transform's "up" isn't
/// reliably up there, while SwiftUI's offset always is.
struct MissedReminderHop: ViewModifier {
    let isActive: Bool
    var height: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content.keyframeAnimator(initialValue: CGFloat(0), repeating: true) { view, hop in
                view.offset(y: -hop)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(height, duration: 0.16)
                    CubicKeyframe(0, duration: 0.16)
                    CubicKeyframe(height * 0.45, duration: 0.11)
                    CubicKeyframe(0, duration: 0.11)
                    LinearKeyframe(0, duration: 1.26)
                }
            }
        } else {
            content
        }
    }
}

/// The widget's "look at me" bounce: it squashes, hops and lands, twice,
/// then rests. Scales down before hopping so the card never leaves its own
/// window — anything outside would be clipped. Core Animation runs it, so
/// it costs the app nothing per frame.
enum WidgetBounce {
    static let key = "missedReminderBounce"

    /// (time 0...1, scale, hop as a share of the card's height)
    private static let frames: [(time: Double, scale: CGFloat, hop: CGFloat)] = [
        (0, 1, 0), (0.08, 0.95, 0), (0.2, 0.93, 0.035), (0.34, 1, 0),
        (0.44, 0.97, 0.015), (0.54, 1, 0), (1, 1, 0)
    ]

    /// Transforms for a layer whose anchor point is its origin (AppKit's
    /// default for a view's backing layer), scaling about the centre.
    static func transforms(size: CGSize) -> [CATransform3D] {
        frames.map { frame in
            let centre = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
            let scaled = CATransform3DConcat(centre, CATransform3DMakeScale(frame.scale, frame.scale, 1))
            return CATransform3DConcat(scaled, CATransform3DMakeTranslation(size.width / 2, size.height / 2 + frame.hop * size.height, 0))
        }
    }

    static func animation(size: CGSize) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transforms(size: size).map { NSValue(caTransform3D: $0) }
        animation.keyTimes = frames.map { NSNumber(value: $0.time) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: frames.count - 1)
        animation.duration = 1.8
        animation.repeatCount = .infinity
        return animation
    }
}
