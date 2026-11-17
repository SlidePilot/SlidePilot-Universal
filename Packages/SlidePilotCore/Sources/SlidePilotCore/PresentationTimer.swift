import Foundation

/// What the presenter's time display counts (TIME-04).
public enum TimeMode: String, Sendable, CaseIterable {
    /// Counts up from 00:00:00 (TIME-02).
    case stopwatch
    /// Counts down from the set time and continues into negative overtime (TIME-03).
    case timer
}

/// The stopwatch and timer of one presentation (TIME-02 to TIME-05, TIME-07).
///
/// The time is measured from the start instants, not by counting ticks, so it does not
/// drift (TIME-07; the old app counted 1-second ticks, DEF-08). Every method takes the
/// current time, so tests can drive it without waiting.
public struct PresentationTimer: Sendable, Equatable {
    /// The app starts in stopwatch mode; the mode is not saved (TIME-04).
    public private(set) var mode: TimeMode
    /// The time the timer counts down from, in whole seconds (TIME-03).
    public private(set) var timerDuration: Int = 0
    /// Whether the first "next slide" from the keyboard or menu still starts the time (TIME-05).
    public private(set) var startsOnNextSlide = true

    /// Time measured in earlier runs since the last reset.
    private var accumulated: TimeInterval = 0
    /// Start of the current run; `nil` while stopped.
    private var runningSince: Date?

    public init(mode: TimeMode = .stopwatch) {
        self.mode = mode
    }

    public var isRunning: Bool { runningSince != nil }

    /// Time measured since the last reset.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(runningSince))
    }

    /// The value to show in whole seconds: the stopwatch counts up, the timer counts down
    /// from `timerDuration` and becomes negative in overtime. Like the old app, the value
    /// changes once a full second has passed.
    public func displayedSeconds(at now: Date) -> Int {
        // The tolerance absorbs floating-point error when a display tick lands exactly on
        // a whole second (see `tickAnchor`).
        let seconds = Int((elapsed(at: now) + 0.001).rounded(.down))
        switch mode {
        case .stopwatch: return seconds
        case .timer: return timerDuration - seconds
        }
    }

    /// The timer is past zero (TIME-03). Zero itself is not overtime.
    public func isOvertime(at now: Date) -> Bool {
        mode == .timer && displayedSeconds(at: now) < 0
    }

    /// While running: the instant at which the measured time would have been zero. A display
    /// that refreshes every second from this instant changes exactly when the value does.
    public var tickAnchor: Date? {
        runningSince.map { $0.addingTimeInterval(-accumulated) }
    }

    // MARK: - Commands

    /// Start/Stop Time pressed by the presenter (TIME-02). A manual start or stop turns
    /// off the auto-start (TIME-05).
    public mutating func toggle(at now: Date = Date()) {
        startsOnNextSlide = false
        if isRunning {
            stop(at: now)
        } else {
            start(at: now)
        }
    }

    /// Starts the time on the first "next slide" from the keyboard or menu of a document
    /// (TIME-05, NAV-09). Later calls do nothing.
    public mutating func nextSlideCommandWasUsed(at now: Date = Date()) {
        guard startsOnNextSlide else { return }
        startsOnNextSlide = false
        start(at: now)
    }

    /// Stops and goes back to zero (stopwatch) or to the set time (timer) (TIME-02, TIME-03).
    public mutating func reset() {
        runningSince = nil
        accumulated = 0
    }

    /// Switches between stopwatch and timer. Like the old app this stops and resets the time,
    /// also when the current mode is chosen again, but the set timer duration is kept (DEF-08).
    public mutating func setMode(_ newMode: TimeMode) {
        mode = newMode
        reset()
    }

    /// Set Timer (TIME-03): only in timer mode. Like the old app the timer stops and shows
    /// the new time. Negative values count as zero.
    public mutating func setTimerDuration(_ seconds: Int) {
        guard mode == .timer else { return }
        timerDuration = max(0, seconds)
        reset()
    }

    private mutating func start(at now: Date) {
        guard !isRunning else { return }
        runningSince = now
    }

    private mutating func stop(at now: Date) {
        accumulated = elapsed(at: now)
        runningSince = nil
    }
}

/// Formats stopwatch and timer values like the old app: `HH:MM:SS`, overtime as
/// `- HH:MM:SS` (TIME-03). Hours are not limited to two digits.
public enum TimerValueFormat {
    public static func string(seconds: Int) -> String {
        guard seconds >= 0 else { return "- " + string(seconds: -seconds) }
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return "\(twoDigits(hours)):\(twoDigits(minutes)):\(twoDigits(seconds % 60))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// Splits a duration in whole seconds into the fields of the Set Timer picker (TIME-03).
public struct TimerDurationComponents: Sendable, Equatable {
    public var hours: Int
    public var minutes: Int
    public var seconds: Int

    public static let hourRange = 0...23
    public static let minuteRange = 0...59
    public static let secondRange = 0...59

    public init(hours: Int, minutes: Int, seconds: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    /// Durations beyond the picker's range are shown as 23:59:59.
    public init(totalSeconds: Int) {
        let clamped = min(max(totalSeconds, 0), 23 * 3600 + 59 * 60 + 59)
        self.init(hours: clamped / 3600, minutes: clamped / 60 % 60, seconds: clamped % 60)
    }

    /// Each field clamped to its range.
    public var totalSeconds: Int {
        func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
            min(max(value, range.lowerBound), range.upperBound)
        }
        return clamp(hours, Self.hourRange) * 3600
            + clamp(minutes, Self.minuteRange) * 60
            + clamp(seconds, Self.secondRange)
    }
}

/// Size of the clock and stopwatch/timer in the presenter (TIME-06). Global, not per
/// document (LAY-05). The raw values match the old app's `timeSize` user default.
public enum TimeDisplaySize: Int, Sendable, CaseIterable {
    case hidden = 0
    case small = 1
    case normal = 2

    /// The user-defaults key, the same as in the old app.
    public static let defaultsKey = "timeSize"
    public static let `default` = TimeDisplaySize.normal
}
