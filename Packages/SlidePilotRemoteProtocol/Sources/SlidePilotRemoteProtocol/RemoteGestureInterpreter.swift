import Foundation

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

        func distance(to other: Point) -> Double {
            hypot(other.x - x, other.y - y)
        }
    }

    /// The shortest horizontal movement that counts as a swipe.
    public static let swipeDistance = 50.0
    /// A touch that moves less than this is a tap.
    public static let tapMovement = 12.0
    /// A tap lasts at most this long (seconds).
    public static let tapDuration = 0.3
    /// The second touch of a double tap starts within this time after the first tap ends.
    public static let doubleTapInterval = 0.35
    /// … and this close to it.
    public static let doubleTapDistance = 40.0

    private struct Touch: Sendable, Equatable {
        let start: Point
        let startTime: Double
        let movesPointer: Bool
        var isCancelled = false
    }

    private struct Tap: Sendable, Equatable {
        let point: Point
        let time: Double
    }

    private var touch: Touch?
    private var lastTap: Tap?

    public init() {}

    /// Whether the current touch moves the pointer.
    public var isMovingPointer: Bool { touch?.movesPointer == true && touch?.isCancelled == false }

    /// The touch started at `start` and is now at `location`. `slidePosition` is `location`
    /// relative to the slide (0…1, origin top left).
    public mutating func moved(
        start: Point, location: Point, time: Double, slidePosition: PointerPosition
    ) -> [ControllerCommand] {
        if touch == nil || touch?.start != start {
            touch = Touch(start: start, startTime: time, movesPointer: isSecondTap(at: start, time: time))
            lastTap = nil
        }
        guard let touch, !touch.isCancelled, touch.movesPointer else { return [] }
        return [.pointerMoved(slidePosition)]
    }

    /// The touch ended at `location`.
    public mutating func ended(start: Point, location: Point, time: Double) -> [ControllerCommand] {
        defer { touch = nil }
        guard let touch, !touch.isCancelled else {
            // A cancelled touch already finished its pointer.
            lastTap = nil
            return []
        }
        if touch.movesPointer {
            lastTap = nil
            return [.pointerFinished]
        }
        let dx = location.x - start.x
        let dy = location.y - start.y
        if abs(dx) >= Self.swipeDistance, abs(dx) > abs(dy) {
            lastTap = nil
            // Swiping to the left brings the next slide, like turning a page.
            return [dx < 0 ? .nextSlide : .previousSlide]
        }
        if start.distance(to: location) < Self.tapMovement, time - touch.startTime <= Self.tapDuration {
            lastTap = Tap(point: location, time: time)
        } else {
            lastTap = nil
        }
        return []
    }

    /// A pinch started: the current touch is neither a swipe nor a tap. A pointer it moved
    /// is finished.
    public mutating func cancel() -> [ControllerCommand] {
        lastTap = nil
        guard var touch, !touch.isCancelled else { return [] }
        touch.isCancelled = true
        self.touch = touch
        return touch.movesPointer ? [.pointerFinished] : []
    }

    private func isSecondTap(at point: Point, time: Double) -> Bool {
        guard let lastTap else { return false }
        return time - lastTap.time <= Self.doubleTapInterval && point.distance(to: lastTap.point) <= Self.doubleTapDistance
    }
}
