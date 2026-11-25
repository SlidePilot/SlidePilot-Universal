#if os(iOS)
import SlidePilotCore
import SwiftUI
import TipKit
import UIKit

/// The double tap and hold gesture on the presenter's current slide (PTR-01): the held
/// second touch of a double tap points, dragging moves the pointer, lifting hides it.
///
/// A UIKit recognizer, because SwiftUI has no gesture that stays out of the way of swipes
/// and link taps until a touch turns out to be the second touch of a double tap. The timing
/// is `DoubleTapHoldGesture` (SlidePilotCore), shared with the remote controller (REM-07).
struct TouchPointerGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let began: () -> Void
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    func makeUIGestureRecognizer(context: Context) -> DoubleTapHoldRecognizer {
        DoubleTapHoldRecognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: DoubleTapHoldRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: DoubleTapHoldRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            began()
            moved(context.converter.localLocation)
        case .changed:
            moved(context.converter.localLocation)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }
}

/// Feeds one finger's touches into `DoubleTapHoldGesture` and begins only for the held
/// second touch of a double tap. Until then it neither delays nor takes touches, so swipes,
/// link taps and video controls work as before.
final class DoubleTapHoldRecognizer: UIGestureRecognizer {
    private var gesture = DoubleTapHoldGesture()
    private var touch: UITouch?

    init() {
        super.init(target: nil, action: nil)
        // Fingers and Pencil; trackpad and mouse point by hovering.
        allowedTouchTypes = [UITouch.TouchType.direct, .pencil].map { NSNumber(value: $0.rawValue) }
        delaysTouchesEnded = false
    }

    private var isPointing: Bool { state == .began || state == .changed }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touch == nil, touches.count == 1, let first = touches.first else {
            // A second finger (pinch, two-finger scroll) is no double tap.
            gesture.cancel()
            state = isPointing ? .cancelled : .failed
            return
        }
        touch = first
        if gesture.began(at: first.location(in: nil), time: first.timestamp) {
            state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch), isPointing else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch) else { return }
        let wasPointing = isPointing
        gesture.ended(at: touch.location(in: nil), time: touch.timestamp)
        state = wasPointing ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        gesture.cancel()
        state = isPointing ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        // `gesture` keeps the last tap across touches; only the touch is forgotten.
        touch = nil
    }
}

/// Delays following a link on the current slide by the double tap interval, so a double
/// tap and hold that starts on a link points instead (PTR-01). A single tap still follows
/// the link, just slightly later.
@MainActor
final class LinkTapDelay {
    private var pending: Task<Void, Never>?
    private var isPointing = false
    private var lastPointingEnd: ContinuousClock.Instant?

    func follow(_ action: @escaping @MainActor () -> Void) {
        // The held touch may end as a tap on the link; it pointed, so it does not follow.
        if isPointing { return }
        if let lastPointingEnd, ContinuousClock.now - lastPointingEnd < .milliseconds(100) { return }
        pending?.cancel()
        pending = Task {
            // A margin over the recognizer's limit, so a late second touch still wins.
            try? await Task.sleep(for: .seconds(DoubleTapHoldGesture.doubleTapInterval + 0.05))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func pointingBegan() {
        cancel()
        isPointing = true
    }

    func pointingEnded() {
        isPointing = false
        lastPointingEnd = .now
    }

    /// Drops a pending follow, e.g. when the slide changes before it runs.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

extension EnvironmentValues {
    /// Set on the presenter's current slide on iPad; links elsewhere follow at once.
    @Entry var linkTapDelay: LinkTapDelay?
}

/// Explains the double tap and hold gesture, which cannot be guessed (PTR-01). Shown once
/// above the slides after the external display tip (`externalDisplayHint()`); invalidated
/// when it is dismissed or once the gesture has been used.
struct TouchPointerTip: Tip {
    var title: Text { Text("Point with your finger") }
    var message: Text? {
        Text("Double-tap and hold the current slide to show the pointer to the audience. Drag to move it, lift your finger to hide it.")
    }
    var image: Image? { Image(systemName: "hand.point.up.left") }
}
#endif
