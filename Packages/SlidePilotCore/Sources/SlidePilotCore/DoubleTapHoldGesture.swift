import CoreGraphics
import Foundation

/// Recognizes a double tap whose second touch stays down: the touch gesture that points
/// on a slide (PTR-01 on the presenter's current slide, REM-07 on the remote controller).
/// The second touch holds the pointer until it lifts; dragging it moves the pointer.
///
/// Feed it one finger's touches in order. Times are seconds on any monotonic clock, points
/// are in one coordinate space.
public struct DoubleTapHoldGesture: Sendable, Equatable {
    /// A touch that moves less than this (points) is a tap.
    public static let tapMovement = 12.0
    /// A tap lasts at most this long (seconds).
    public static let tapDuration = 0.3
    /// The second touch starts within this time after the first tap ends …
    public static let doubleTapInterval = 0.35
    /// … and this close to it (points).
    public static let doubleTapDistance = 40.0

    private struct Touch: Sendable, Equatable {
        let start: CGPoint
        let startTime: Double
        let isHolding: Bool
        var isCancelled = false
    }

    private struct Tap: Sendable, Equatable {
        let point: CGPoint
        let time: Double
    }

    private var touch: Touch?
    private var lastTap: Tap?

    public init() {}

    /// Whether the current touch is the held second touch of a double tap.
    public var isHolding: Bool { touch?.isHolding == true && touch?.isCancelled == false }

    /// Whether a touch is down and not cancelled.
    public var isTracking: Bool { touch != nil && touch?.isCancelled == false }

    /// A finger touched down at `point`. Returns whether this touch holds the pointer.
    @discardableResult
    public mutating func began(at point: CGPoint, time: Double) -> Bool {
        let isHolding = isSecondTap(at: point, time: time)
        touch = Touch(start: point, startTime: time, isHolding: isHolding)
        lastTap = nil
        return isHolding
    }

    /// The finger lifted at `point`. A short touch that barely moved counts as the first tap
    /// of a double tap; the held touch does not, so a triple tap points only once.
    public mutating func ended(at point: CGPoint, time: Double) {
        defer { touch = nil }
        guard let touch, !touch.isCancelled, !touch.isHolding else {
            lastTap = nil
            return
        }
        let isTap = Self.distance(touch.start, point) < Self.tapMovement && time - touch.startTime <= Self.tapDuration
        lastTap = isTap ? Tap(point: point, time: time) : nil
    }

    /// The touch was taken over (a second finger, a pinch, the system): it is no tap, and a
    /// pointer it held ends. Returns whether it held the pointer.
    @discardableResult
    public mutating func cancel() -> Bool {
        lastTap = nil
        guard var touch, !touch.isCancelled else { return false }
        touch.isCancelled = true
        self.touch = touch
        return touch.isHolding
    }

    private func isSecondTap(at point: CGPoint, time: Double) -> Bool {
        guard let lastTap else { return false }
        return time - lastTap.time <= Self.doubleTapInterval
            && Self.distance(point, lastTap.point) <= Self.doubleTapDistance
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }
}
