import SwiftUI
import AppKit

/// Draws one split-flap card: the static top and bottom halves plus the
/// animating flap. On a value change it plays the two-phase rotation:
/// phase 1 shows the OLD value's top half falling from flat to edge-on,
/// phase 2 shows the NEW value's bottom half continuing from edge-on down
/// to flat. Content is swapped only at the edge-on midpoint, where the
/// layer is visually foreshortened to a sliver — this is what avoids the
/// classic "mirrored text" bug that comes from rotating a single face past
/// 90° with `rotation3DEffect`.
///
/// The static halves live here rather than in SwiftUI so they can be masked
/// in lockstep with the flap. Glass cards are translucent, so the flap can't
/// simply cover the static half beneath it the way a solid leaf does — the
/// half under it would show straight through as a double exposure. Instead
/// each static half is masked to exactly the part the flap isn't over.
struct FlipCardLayer: NSViewRepresentable {
    struct Style: Equatable {
        var isDark: Bool
        var glassCard: Bool
        var textColor: NSColor?
        var tintsIcons: Bool
        var fontName: String?
        var isMonospacedSystemFont: Bool
        var hingeThickness: CGFloat
    }

    let value: String
    let cardSize: CGSize
    let style: Style
    /// Styles this card may switch to next (the other widget looks). Their
    /// faces are rendered ahead of time, so a vivid <-> dimmed switch never
    /// has to rasterise glyphs on the frame it starts.
    var upcomingStyles: [Style] = []

    func makeNSView(context: Context) -> FlapAnimatingNSView {
        let view = FlapAnimatingNSView(value: value)
        view.update(cardSize: cardSize, style: style)
        return view
    }

    func updateNSView(_ nsView: FlapAnimatingNSView, context: Context) {
        nsView.upcomingStyles = upcomingStyles
        nsView.update(cardSize: cardSize, style: style)
        nsView.show(value)
    }
}

final class FlapAnimatingNSView: NSView {
    private let topLayer = CALayer()
    private let bottomLayer = CALayer()
    private let topMask = CALayer()
    private let bottomMask = CALayer()
    private let flapLayer = CALayer()

    private var cardSize: CGSize = .zero
    private var style: FlipCardLayer.Style?
    var upcomingStyles: [FlipCardLayer.Style] = []
    /// What the static top/bottom halves currently show. They diverge only
    /// mid-flip: the top shows the new value from the start, the bottom
    /// keeps the old one until the flap lands on it.
    private var topValue: String
    private var bottomValue: String
    /// Latest value asked for.
    private var targetValue: String
    /// Guards against re-entrant flips. A source value that changes faster
    /// than one flip cycle takes (~0.33s) — the stopwatch's centisecond
    /// digit ticks every 30ms — used to retrigger the flip mid-rotation and
    /// leave two animations fighting over the same transform, which could
    /// freeze a digit mid-rotation for good. Rapid changes are coalesced
    /// into "play the latest target once the current flip lands", so exactly
    /// one flip is ever in flight.
    private var isFlipping = false

    private static let phase1Duration: CFTimeInterval = 0.15
    private static let phase2Duration: CFTimeInterval = 0.18
    /// How far into the gap before the next change a flip may run.
    private static let pacingHeadroom: Double = 0.85

    /// Smoothed time between this card's value changes, and the multiplier
    /// it puts on the flip's duration. A fixed 0.33s flip on a digit that
    /// changes every 30-100ms (the stopwatch's hundredths) was interrupted
    /// by the next value on nearly every change, so it never showed a flip —
    /// just a coalesced jump, reading as a glitchy timelapse. Pacing the flip
    /// to the card's own rate lets every change it's given land as a complete
    /// flip. Cards that change once a second or slower keep the full speed.
    private var changeInterval: CFTimeInterval = .infinity
    private var lastChangeTime: CFTimeInterval = 0
    private var durationScale: Double = 1

    static func durationScale(forChangeInterval interval: CFTimeInterval) -> Double {
        min(1, interval * pacingHeadroom / (phase1Duration + phase2Duration))
    }

    private func recordChange() {
        let now = CACurrentMediaTime()
        let interval = now - lastChangeTime
        lastChangeTime = now
        // Averaged so one late tick doesn't make the next flip lurch slower.
        changeInterval = changeInterval.isFinite ? (changeInterval + interval) / 2 : interval
        durationScale = Self.durationScale(forChangeInterval: changeInterval)
    }

    private var phase1: CFTimeInterval { Self.phase1Duration * durationScale }
    private var phase2: CFTimeInterval { Self.phase2Duration * durationScale }
    private static let phase1Timing = CAMediaTimingFunction(name: .easeIn)
    /// Slight overshoot then settle — the mechanical "clack" of a real leaf
    /// hitting its stop, rather than a smooth ease.
    private static let phase2Timing = CAMediaTimingFunction(controlPoints: 0.34, 1.2, 0.64, 1)
    private static let maskSamples = 16

    init(value: String) {
        topValue = value
        bottomValue = value
        targetValue = value
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

        for half in [topLayer, bottomLayer] {
            half.contentsGravity = .resize
            layer?.addSublayer(half)
        }
        topMask.backgroundColor = NSColor.black.cgColor
        topMask.anchorPoint = CGPoint(x: 0, y: 1)
        bottomMask.backgroundColor = NSColor.black.cgColor
        bottomMask.anchorPoint = .zero
        topLayer.mask = topMask
        bottomLayer.mask = bottomMask

        flapLayer.isHidden = true
        flapLayer.isDoubleSided = false
        flapLayer.contentsGravity = .resize
        flapLayer.shadowColor = NSColor.black.cgColor
        layer?.addSublayer(flapLayer)
    }

    /// Whole points, not `cardSize.height / 2`: scaled card sizes land on
    /// fractions (72.15pt at 3×), and a fractional half-card bitmap gets
    /// resampled into its layer, softening both leaves' edges exactly where
    /// they meet — the hinge line came out as two faint bands with a pale row
    /// between them instead of one crisp seam. Any leftover fraction just
    /// leaves a sliver of bare platter at the card's top edge.
    private var halfHeight: CGFloat { (cardSize.height / 2).rounded(.down) }
    private var faceSize: CGSize { CGSize(width: cardSize.width, height: halfHeight * 2) }

    func update(cardSize: CGSize, style: FlipCardLayer.Style) {
        guard cardSize != self.cardSize || style != self.style else { return }
        let restyled = self.style != nil && style != self.style
        self.cardSize = cardSize
        self.style = style

        CATransaction.begin()
        // A tone change (vivid <-> dimmed) crossfades the glyphs the way the
        // system's widgets fade; a resize or first layout must not animate.
        let animateRestyle = restyled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.setDisableActions(!animateRestyle)
        CATransaction.setAnimationDuration(GlassTone.transitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .default))
        let half = CGRect(x: 0, y: 0, width: cardSize.width, height: halfHeight)
        topLayer.frame = half.offsetBy(dx: 0, dy: halfHeight)
        bottomLayer.frame = half
        topMask.bounds = half
        topMask.position = CGPoint(x: 0, y: halfHeight)
        bottomMask.bounds = half
        bottomMask.position = .zero
        topLayer.contents = face(topValue, top: true)
        bottomLayer.contents = face(bottomValue, top: false)
        CATransaction.commit()
        prewarm(topValue)
    }

    private func face(_ value: String, top: Bool, flap: Bool = false) -> CGImage? {
        guard let style else { return nil }
        return face(value, top: top, flap: flap, style: style)
    }

    private func face(_ value: String, top: Bool, flap: Bool = false, style: FlipCardLayer.Style) -> CGImage? {
        guard cardSize.width > 0, cardSize.height > 0 else { return nil }
        // Solid cards bake their leaf colour into every half. Glass statics
        // are glyph-only (the SwiftUI platter behind supplies the tint); the
        // glass flap adds only a faint shade so it reads as a turning leaf
        // without doubling the platter's tint.
        let fill: NSColor? = style.glassCard && flap ? FlapColors.glassFlapShade : nil
        return DigitFaceRenderer.halfFace(
            for: value,
            cardSize: faceSize,
            top: top,
            isDark: style.isDark,
            textColor: style.textColor,
            transparentBackground: style.glassCard && !flap,
            fillColor: fill,
            fontName: style.fontName,
            isMonospacedSystemFont: style.isMonospacedSystemFont,
            hingeThickness: style.hingeThickness,
            tintsIcons: style.tintsIcons
        )
    }

    func show(_ value: String) {
        guard value != targetValue else { return }
        targetValue = value
        recordChange()
        guard !isFlipping else { return }
        play(value)
    }

    /// Flips (or, under Reduce Motion, snaps) from what the bottom half shows
    /// to `value`. Also used for a value that arrived mid-flip, which is why
    /// it's separate from `show` — that one records the change for pacing.
    private func play(_ value: String) {
        guard cardSize.width > 0, cardSize.height > 0,
              // HIG: Reduce Motion replaces decorative motion with an instant
              // change.
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            land(on: value)
            return
        }
        beginFlip(from: bottomValue, to: value)
    }

    private func land(on value: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topValue = value
        bottomValue = value
        topLayer.contents = face(value, top: true)
        bottomLayer.contents = face(value, top: false)
        CATransaction.commit()
        prewarm(value)
    }

    /// Renders (into `DigitFaceRenderer`'s cache) the faces this value would
    /// need in each upcoming style, one run-loop turn later so it never adds
    /// to the frame that's showing the value now.
    private func prewarm(_ value: String) {
        let styles = upcomingStyles
        guard !styles.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for style in styles {
                _ = self.face(value, top: true, style: style)
                _ = self.face(value, top: false, style: style)
            }
        }
    }

    /// Height of a static half left uncovered while the flap, hinged at the
    /// card's middle, sits at `angle` from flat. One point is held back so a
    /// rounding difference can only ever leave a hairline of bare platter,
    /// never a hairline of the half underneath showing through.
    private func uncoveredHeight(angle: CGFloat) -> CGFloat {
        max(0, halfHeight * (1 - cos(angle)) - 1)
    }

    /// Keyframes for a mask's height across the flap's rotation. They use the
    /// flap's own timing function, so mask and flap are driven by the same
    /// progress curve and stay in lockstep.
    private func maskAnimation(from startAngle: CGFloat, to endAngle: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: "bounds.size.height")
        anim.values = (0...Self.maskSamples).map { step -> CGFloat in
            let progress = CGFloat(step) / CGFloat(Self.maskSamples)
            return uncoveredHeight(angle: startAngle + (endAngle - startAngle) * progress)
        }
        anim.keyTimes = (0...Self.maskSamples).map { NSNumber(value: Double($0) / Double(Self.maskSamples)) }
        anim.duration = duration
        anim.timingFunction = timing
        return anim
    }

    private func beginFlip(from oldValue: String, to newValue: String) {
        isFlipping = true
        let isGlass = style?.glassCard ?? false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topValue = newValue
        topLayer.contents = face(newValue, top: true)
        flapLayer.isHidden = false
        flapLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        flapLayer.bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: halfHeight)
        flapLayer.position = CGPoint(x: cardSize.width / 2, y: halfHeight)
        flapLayer.contents = face(oldValue, top: true, flap: true)
        flapLayer.transform = CATransform3DIdentity
        // A drop shadow on a glass leaf reads as a stray dark smudge
        // sweeping past the hinge line as the flap rotates — only the
        // opaque, non-glass mechanical card style wants that depth cue.
        flapLayer.shadowOpacity = isGlass ? 0 : 0.25
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
        anim.duration = phase1
        anim.timingFunction = Self.phase1Timing
        flapLayer.add(anim, forKey: "flipPhase1")
        if isGlass {
            topMask.add(maskAnimation(from: 0, to: .pi / 2, duration: phase1, timing: Self.phase1Timing), forKey: "reveal")
        }
        CATransaction.commit()
    }

    private func startPhase2(newValue: String) {
        let startAngle = CGFloat.pi / 2
        let isGlass = style?.glassCard ?? false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flapLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        flapLayer.bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: halfHeight)
        flapLayer.position = CGPoint(x: cardSize.width / 2, y: halfHeight)
        flapLayer.contents = face(newValue, top: false, flap: true)
        flapLayer.transform = CATransform3DMakeRotation(startAngle, 1, 0, 0)
        CATransaction.commit()

        CATransaction.begin()
        // Same reasoning as phase 1 — disable implicit actions so only the
        // explicit animation below drives the transform.
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.flapLayer.isHidden = true
            self.bottomMask.removeAnimation(forKey: "cover")
            self.land(on: newValue)
            self.isFlipping = false
            // A newer value arrived while this flip was still rotating —
            // play it now that the layer has cleanly landed, rather than
            // in the middle of the animation that was already running.
            if self.targetValue != newValue {
                self.play(self.targetValue)
            }
        }
        flapLayer.transform = CATransform3DIdentity
        let anim = CABasicAnimation(keyPath: "transform.rotation.x")
        anim.fromValue = startAngle
        anim.toValue = 0
        anim.duration = phase2
        anim.timingFunction = Self.phase2Timing
        flapLayer.add(anim, forKey: "flipPhase2")
        if isGlass {
            let cover = maskAnimation(from: startAngle, to: 0, duration: phase2, timing: Self.phase2Timing)
            // Holds the fully-covered end state until the completion block
            // swaps the bottom half's content, so the old value can't flash
            // back for a frame in between.
            cover.fillMode = .forwards
            cover.isRemovedOnCompletion = false
            bottomMask.add(cover, forKey: "cover")
        }
        CATransaction.commit()
    }
}
