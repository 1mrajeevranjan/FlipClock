import SwiftUI
import AppKit

/// The animating flap for one digit position. Renders nothing visible when
/// idle (the static top/bottom halves drawn by the parent `SplitFlapDigit`
/// show through) — on a digit change it plays the two-phase rotation:
/// phase 1 shows the OLD digit's top half falling from flat to edge-on,
/// phase 2 shows the NEW digit's bottom half continuing from edge-on down
/// to flat. Content is swapped only at the edge-on midpoint, where the
/// layer is visually foreshortened to a sliver — this is what avoids the
/// classic "mirrored text" bug that comes from rotating a single face past
/// 90° with `rotation3DEffect`.
struct FlipCardLayer: NSViewRepresentable {
    let value: String
    let cardSize: CGSize
    let isDark: Bool
    var glassCard: Bool = false
    var onLanded: () -> Void = {}

    func makeNSView(context: Context) -> FlapAnimatingNSView {
        let view = FlapAnimatingNSView()
        view.configure(cardSize: cardSize)
        context.coordinator.lastValue = value
        return view
    }

    func updateNSView(_ nsView: FlapAnimatingNSView, context: Context) {
        nsView.onLanded = onLanded
        nsView.isDark = isDark
        nsView.glassCard = glassCard
        nsView.configure(cardSize: cardSize)
        guard context.coordinator.lastValue != value else { return }
        let old = context.coordinator.lastValue
        context.coordinator.lastValue = value
        nsView.playFlip(oldValue: old, newValue: value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastValue: value)
    }

    final class Coordinator {
        var lastValue: String
        init(lastValue: String) { self.lastValue = lastValue }
    }
}

final class FlapAnimatingNSView: NSView {
    var onLanded: (() -> Void)?
    var isDark: Bool = true
    var glassCard: Bool = false

    private let flapLayer = CALayer()
    private var cardSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // A deeper (less negative) m34 flattens the perspective — the
        // previous, stronger value made the flap visibly bow/shift
        // sideways as it rotated through the middle of the animation,
        // reading as a "jump" each time the seconds digit ticked over.
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 2400.0
        layer?.sublayerTransform = perspective

        flapLayer.isHidden = true
        flapLayer.isDoubleSided = false
        flapLayer.contentsGravity = .resize
        flapLayer.shadowColor = NSColor.black.cgColor
        layer?.addSublayer(flapLayer)
    }

    func configure(cardSize: CGSize) {
        guard cardSize != self.cardSize else { return }
        self.cardSize = cardSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flapLayer.bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height / 2)
        flapLayer.position = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        CATransaction.commit()
    }

    func playFlip(oldValue: String, newValue: String) {
        guard cardSize.width > 0, cardSize.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flapLayer.isHidden = false
        flapLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        flapLayer.bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height / 2)
        flapLayer.position = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        flapLayer.contents = DigitFaceRenderer.halfFace(for: oldValue, cardSize: cardSize, top: true, isDark: isDark, textColor: nil, fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark)) : nil)
        flapLayer.transform = CATransform3DIdentity
        // A drop shadow on a glass leaf reads as a stray dark smudge
        // sweeping past the hinge line as the flap rotates — only the
        // opaque, non-glass mechanical card style wants that depth cue.
        flapLayer.shadowOpacity = glassCard ? 0 : 0.25
        flapLayer.shadowRadius = 1.5
        flapLayer.shadowOffset = CGSize(width: 0, height: -0.5)
        CATransaction.commit()

        let toAngle = -CGFloat.pi / 2
        CATransaction.begin()
        // Without this, the plain `transform` assignment below ALSO
        // triggers CALayer's own implicit action for that keypath (default
        // ~0.25s ease) running alongside the explicit animation we add
        // right after — two competing transforms on the same layer, which
        // is what read as the digit "merging"/double-exposing mid-flip.
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            self?.startPhase2(newValue: newValue)
        }
        flapLayer.transform = CATransform3DMakeRotation(toAngle, 1, 0, 0)
        let anim = CABasicAnimation(keyPath: "transform.rotation.x")
        anim.fromValue = 0
        anim.toValue = toAngle
        anim.duration = 0.15
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        flapLayer.add(anim, forKey: "flipPhase1")
        CATransaction.commit()
    }

    private func startPhase2(newValue: String) {
        let startAngle = CGFloat.pi / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flapLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        flapLayer.bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height / 2)
        flapLayer.position = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        flapLayer.contents = DigitFaceRenderer.halfFace(for: newValue, cardSize: cardSize, top: false, isDark: isDark, textColor: nil, fillColor: glassCard ? NSColor(FlapColors.frostedCard(isDark: isDark)) : nil)
        flapLayer.transform = CATransform3DMakeRotation(startAngle, 1, 0, 0)
        CATransaction.commit()

        CATransaction.begin()
        // Same reasoning as phase 1 — disable implicit actions so only the
        // explicit animation below drives the transform.
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            self?.flapLayer.isHidden = true
            self?.onLanded?()
        }
        flapLayer.transform = CATransform3DIdentity
        let anim = CABasicAnimation(keyPath: "transform.rotation.x")
        anim.fromValue = startAngle
        anim.toValue = 0
        anim.duration = 0.18
        // Slight overshoot then settle — the mechanical "clack" of a real
        // leaf hitting its stop, rather than a smooth ease.
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.2, 0.64, 1)
        flapLayer.add(anim, forKey: "flipPhase2")
        CATransaction.commit()
    }
}
