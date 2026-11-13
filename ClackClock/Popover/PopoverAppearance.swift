import SwiftUI

struct PopoverControlSurface: ViewModifier {
    var tint: Color = .clear
    var cornerRadius: CGFloat = 10
    var usesClearGlass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(tint, in: shape)
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.25)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect((usesClearGlass ? Glass.clear : Glass.regular).tint(tint).interactive(!usesClearGlass), in: shape)
        } else {
            content
                .background(tint, in: shape)
                .background(Color.primary.opacity(0.055), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.1)))
        }
    }
}

struct PopoverCardSurface: ViewModifier {
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : tint.opacity(0.035), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.25 : 0.08)))
    }
}

struct PopoverPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.2), value: configuration.isPressed)
    }
}

struct PopoverEntrance<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motionReduced = reduceMotion
        // Animate only presentation transforms; popover sizing must settle immediately.
        return content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, progress in
            view
                .opacity(motionReduced ? 1 : min(1, 0.6 + progress * 0.4))
                .scaleEffect(motionReduced ? 1 : 0.975 + progress * 0.025, anchor: .top)
                .offset(y: motionReduced ? 0 : (1 - progress) * 6)
        } keyframes: { _ in
            MoveKeyframe(motionReduced ? 1.0 : 0.0)
            SpringKeyframe(1.0, spring: .init(duration: 0.32, bounce: 0.18))
        }
    }
}

extension View {
    @ViewBuilder
    func popoverActionButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) }
            else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) }
            else { self.buttonStyle(.bordered) }
        }
    }
}
