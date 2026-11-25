import Observation

/// Where a trial session stands (PRO-01).
public enum TrialPhase: Sendable, Equatable {
    /// Pro is unlocked (or this is the free Mac download): no limit, no banner.
    case unlimited
    /// The trial runs; the output or connection works and shows the trial banner.
    case running
    /// The time is up: the output stops showing the deck, the remote connection closes.
    /// Only a new session (a new connection) starts a new trial; buying Pro lifts it, but a
    /// closed remote connection stays closed.
    case ended
}

/// The trial of one audience output or one remote connection (PRO-01, ADR 0020).
///
/// Create one when the display connects, the Mac presentation window opens or the user sets
/// up a remote connection, and drop it when that ends. Automatic reconnects keep the old
/// session, so they never start a new trial.
///
/// The phase only moves forward: `running` → `ended`, and from either to `unlimited` once Pro
/// is unlocked. It is re-evaluated in `update(status:at:)`. Time is measured on the monotonic
/// `ContinuousClock`, so changing the system clock cannot stretch a trial, and every method
/// takes the current instant, so tests drive it without waiting.
public struct TrialSession: Sendable, Equatable {
    public typealias Instant = ContinuousClock.Instant

    /// The longest a trial lasts: 3 minutes.
    public static let limit: Duration = .seconds(180)
    /// How long past the deadline a still unknown status may hold off the end. StoreKit answers
    /// within moments; this only keeps a check that never answers from lifting the limit.
    public static let unknownStatusGrace: Duration = .seconds(30)

    public let feature: LimitedFeature
    /// When the output or connection was set up.
    public let startedAt: Instant
    public private(set) var phase: TrialPhase
    /// The last status passed in; decides whether the banner shows.
    public private(set) var status: ProStatus

    public init(feature: LimitedFeature, status: ProStatus, at now: Instant) {
        self.feature = feature
        self.startedAt = now
        self.status = status
        self.phase = .running
        update(status: status, at: now)
    }

    /// When the trial ends if the status is locked; `nil` unless it is running.
    public var deadline: Instant? {
        phase == .running ? startedAt + Self.limit : nil
    }

    /// When the trial ends at the latest with the current status: the deadline, or for an
    /// unknown status the deadline plus `unknownStatusGrace`. `nil` unless it is running.
    public var latestEnd: Instant? {
        guard let deadline else { return nil }
        return status == .unknown ? deadline + Self.unknownStatusGrace : deadline
    }

    /// Time left until the deadline; `nil` unless it is running. Zero while the trial is past
    /// its deadline but the status is still unknown.
    public func remainingTime(at now: Instant) -> Duration? {
        guard let deadline else { return nil }
        return max(.zero, now.duration(to: deadline))
    }

    /// Whether the audience screen shows the "SlidePilot – Trial Version" banner. Not while
    /// the status is unknown, so a Pro user's output never flashes the banner at launch.
    public var showsBanner: Bool {
        phase == .running && status == .locked
    }

    /// Applies the current Pro status and time.
    ///
    /// - An unlocking status lifts the limit at once, also after the end; it stays lifted for
    ///   this session.
    /// - A locked status ends the trial at exactly 3:00; the end is final.
    /// - An unknown status keeps the clock running; the end waits for the status, at most
    ///   `unknownStatusGrace` past the deadline.
    public mutating func update(status: ProStatus, at now: Instant) {
        self.status = status
        if status.unlocksEverything {
            phase = .unlimited
            return
        }
        guard phase == .running, let latestEnd else { return }
        if now >= latestEnd {
            phase = .ended
        }
    }
}

/// Owns the trial session of one audience output or remote connection for the app (PRO-03,
/// PRO-04): it reads the clock, applies Pro status changes and ends the trial in time.
@MainActor
@Observable
public final class TrialCoordinator {
    public typealias Instant = ContinuousClock.Instant

    public private(set) var session: TrialSession

    @ObservationIgnored private let now: () -> Instant
    @ObservationIgnored private let sleep: @MainActor (Instant) async throws -> Void

    /// - Parameters:
    ///   - now: the clock; tests pass a fake one.
    ///   - sleep: waits until the given instant; throws when cancelled. Tests pass one that
    ///     advances their fake clock.
    public init(
        feature: LimitedFeature,
        status: ProStatus,
        now: @escaping () -> Instant = { ContinuousClock.now },
        sleep: @escaping @MainActor (Instant) async throws -> Void = { try await Task.sleep(until: $0, clock: .continuous) }
    ) {
        self.now = now
        self.sleep = sleep
        self.session = TrialSession(feature: feature, status: status, at: now())
    }

    public var phase: TrialPhase { session.phase }
    public var showsBanner: Bool { session.showsBanner }

    /// Time left now; `nil` unless the trial is running.
    public func remainingTime() -> Duration? {
        session.remainingTime(at: now())
    }

    /// Call whenever the app's Pro status changes (in SwiftUI: `onChange(of:initial: true)`, so
    /// a change before the view appeared is not missed). Wakes a waiting `run()`.
    public func statusChanged(_ status: ProStatus) {
        session.update(status: status, at: now())
        wakeUp?.cancel()
    }

    /// Re-evaluates the trial against the clock.
    public func refresh() {
        session.update(status: session.status, at: now())
    }

    /// The pending wait of `run()`; cancelled to wake it after a status change.
    @ObservationIgnored private var wakeUp: Task<Void, Never>?

    /// Waits and ends the trial in time. Returns only once the phase is no longer `running`
    /// (ended or unlimited), or when the calling task is cancelled. Run it once per session in a
    /// task owned by the output or connection, e.g. SwiftUI's `.task`; observe `phase` to react
    /// to the end.
    public func run() async {
        while let end = session.latestEnd, !Task.isCancelled {
            if now() < end {
                let sleep = self.sleep
                // `Task.sleep` throws only when cancelled, i.e. when woken or when run() is
                // cancelled; either way the loop re-evaluates.
                let wait = Task { _ = try? await sleep(end) }
                // An overlapping run() (e.g. a restarted `.task`) re-evaluates instead of
                // sleeping on with a handle nobody can wake.
                wakeUp?.cancel()
                wakeUp = wait
                await withTaskCancellationHandler {
                    await wait.value
                } onCancel: {
                    wait.cancel()
                }
                if wakeUp == wait { wakeUp = nil }
                if Task.isCancelled { return }
            }
            refresh()
        }
    }
}
