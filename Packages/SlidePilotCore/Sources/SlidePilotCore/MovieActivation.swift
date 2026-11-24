import Foundation

/// How a video on a slide plays (NAV-07): the activation of a PDF movie annotation, as
/// Beamer's `\movie` writes it with `autostart`, `loop`, `repeat`, `palindrome`, `once`,
/// `open`, `start` and `duration`.
public struct MovieActivation: Sendable, Hashable {
    /// The PDF's play mode (`/Mode`).
    public enum Mode: String, Sendable, Hashable {
        /// Plays once and stops (the default).
        case once
        /// Plays once and leaves the controls open.
        case open
        /// Plays again and again (Beamer `loop` and `repeat`).
        case `repeat`
        /// Plays forward and backward. Played as a loop: reverse playback does not work
        /// with every codec.
        case palindrome
    }

    public var mode: Mode
    /// Where playback begins, in seconds of the file; `nil` is the beginning.
    public var start: TimeInterval?
    /// How long playback lasts, in seconds; `nil` is to the end of the file.
    public var duration: TimeInterval?
    /// The page plays the video when it is shown (Beamer `autostart`).
    public var autostarts: Bool

    public init(mode: Mode = .once, start: TimeInterval? = nil, duration: TimeInterval? = nil, autostarts: Bool = false) {
        self.mode = mode
        self.start = start
        self.duration = duration
        self.autostarts = autostarts
    }

    /// Whether playback starts over at the end.
    public var loops: Bool { mode == .repeat || mode == .palindrome }

    /// The part of the file to play, in seconds. `end` is `nil` for the end of the file.
    ///
    /// A negative or non-finite start counts as the beginning and a duration that is not
    /// positive as no duration. A start at or past the end of the file (when its length is
    /// known) plays the whole file instead of nothing.
    public func playbackRange(fileDuration: TimeInterval?) -> (start: TimeInterval, end: TimeInterval?) {
        var begin = start.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let length = fileDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        if let length, begin >= length { begin = 0 }
        guard let duration, duration.isFinite, duration > 0 else { return (begin, nil) }
        var end = begin + duration
        if let length { end = min(end, length) }
        return (begin, end)
    }

    /// A PDF time value in seconds: `value` units of `scale` per second (`/Start [640 128]`
    /// is 5 s). A missing or invalid scale means seconds.
    public static func seconds(_ value: Double, scale: Double? = nil) -> TimeInterval? {
        guard value.isFinite else { return nil }
        guard let scale, scale.isFinite, scale > 0 else { return value }
        return value / scale
    }
}
