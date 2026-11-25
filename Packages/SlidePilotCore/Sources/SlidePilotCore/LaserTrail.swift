import Foundation

/// The strokes of the laser pointer (PTR-08): drawn on the current slide, never saved,
/// and gone shortly after the presenter lifts. Strokes drawn in quick succession belong
/// to one gesture: they stay until the last lift, then fade out together, like Keynote.
///
/// Points are relative to the slide surface (0…1, origin top left), like the pointer
/// (PTR-01). Times are seconds on any clock that only moves forward; the views pass
/// `Date.timeIntervalSinceReferenceDate`, tests pass plain numbers.
public struct LaserTrail: Sendable, Equatable {
    /// Fixed look, not configurable (PTR-08).
    public static let color = PointerColor.red
    /// Line width in points of the view that shows the strokes.
    public static let lineWidth = 4.0
    /// Radius of the soft glow around each stroke, in points.
    public static let glowRadius = 6.0
    /// How long the strokes stay after the last lift.
    public static let holdDuration: TimeInterval = 1.5
    /// How long they take to fade out after that (without Reduce Motion).
    public static let fadeDuration: TimeInterval = 0.5

    /// The strokes of the current gesture, oldest first.
    public private(set) var strokes: [[RelativePoint]] = []
    /// Whether a stroke is being drawn right now.
    public private(set) var isDrawing = false
    /// When the last stroke ended; `nil` while drawing or when there are no strokes.
    public private(set) var liftTime: TimeInterval?

    public init() {}

    public var isEmpty: Bool { strokes.isEmpty }

    /// A new stroke starts at `point`. It joins the strokes on screen while they still
    /// stay; once they fade, they are dropped and a new gesture starts.
    public mutating func begin(at point: RelativePoint, time: TimeInterval) {
        if let fadeStart, time >= fadeStart {
            strokes.removeAll()
        }
        strokes.append([point])
        isDrawing = true
        liftTime = nil
    }

    /// The stroke being drawn reaches `point`.
    public mutating func extend(to point: RelativePoint) {
        guard isDrawing, let last = strokes.indices.last, strokes[last].last != point else { return }
        strokes[last].append(point)
    }

    /// The stroke being drawn ended (lift, mouse up or a cancelled touch).
    public mutating func end(time: TimeInterval) {
        guard isDrawing else { return }
        isDrawing = false
        liftTime = time
    }

    /// Removes every stroke at once, e.g. on a slide change.
    public mutating func clear() {
        strokes.removeAll()
        isDrawing = false
        liftTime = nil
    }

    /// When the strokes start to fade; `nil` while drawing or empty.
    public var fadeStart: TimeInterval? {
        liftTime.map { $0 + Self.holdDuration }
    }

    /// When the strokes are fully gone and can be removed.
    public var removalTime: TimeInterval? {
        fadeStart.map { $0 + Self.fadeDuration }
    }

    /// How opaque the strokes are at `time`, 0…1. With Reduce Motion they do not fade:
    /// they vanish at once when the hold time is over.
    public func opacity(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard !strokes.isEmpty else { return 0 }
        guard let fadeStart, time >= fadeStart else { return 1 }
        if reduceMotion { return 0 }
        let progress = (time - fadeStart) / Self.fadeDuration
        return max(0, 1 - progress)
    }

    /// Drops the strokes once they are fully gone.
    public mutating func removeExpired(at time: TimeInterval) {
        if let removalTime, time >= removalTime {
            clear()
        }
    }
}
