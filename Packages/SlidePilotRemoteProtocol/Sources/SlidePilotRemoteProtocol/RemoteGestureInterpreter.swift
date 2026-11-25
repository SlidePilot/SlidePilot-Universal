import CoreGraphics
import Foundation
import SlidePilotCore

/// Turns single-finger touches (or mouse drags) on the controller's slide into commands
/// (REM-07): a horizontal swipe changes the slide, and a double tap whose second touch is
/// held and dragged moves the pointer on the host.
///
/// Pinching is handled by the view; it calls `cancel()` so a pinch is never read as a swipe.
public struct RemoteGestureInterpreter: Sendable {
    /// A point in the view's coordinates (points).
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    }

    /// The shortest horizontal movement that counts as a swipe.
    public static let swipeDistance = 50.0
    /// A touch that moves less than this is a tap.
    public static let tapMovement = DoubleTapHoldGesture.tapMovement

    /// Double tap timing and hold, shared with the presenter's touch pointer (PTR-01).
    private var doubleTap = DoubleTapHoldGesture()
    /// Where the current touch started; a new start is a new touch.
    private var touchStart: Point?

    public init() {}

    /// Whether the current touch moves the pointer.
    public var isMovingPointer: Bool { doubleTap.isHolding }

    /// The touch started at `start` and is now at `location`. `slidePosition` is `location`
    /// relative to the slide (0…1, origin top left).
    public mutating func moved(
        start: Point, location: Point, time: Double, slidePosition: PointerPosition
    ) -> [ControllerCommand] {
        if touchStart != start {
            touchStart = start
            doubleTap.began(at: start.cgPoint, time: time)
        }
        return doubleTap.isHolding ? [.pointerMoved(slidePosition)] : []
    }

    /// The touch ended at `location`.
    public mutating func ended(start: Point, location: Point, time: Double) -> [ControllerCommand] {
        defer { touchStart = nil }
        // A cancelled touch already finished its pointer.
        let isTracking = doubleTap.isTracking && touchStart == start
        let wasHolding = doubleTap.isHolding
        doubleTap.ended(at: location.cgPoint, time: time)
        guard isTracking else { return [] }
        if wasHolding {
            return [.pointerFinished]
        }
        let dx = location.x - start.x
        let dy = location.y - start.y
        if abs(dx) >= Self.swipeDistance, abs(dx) > abs(dy) {
            // Swiping to the left brings the next slide, like turning a page.
            return [dx < 0 ? .nextSlide : .previousSlide]
        }
        return []
    }

    /// A pinch started: the current touch is neither a swipe nor a tap. A pointer it moved
    /// is finished.
    public mutating func cancel() -> [ControllerCommand] {
        doubleTap.cancel() ? [.pointerFinished] : []
    }
}
