import Observation

/// Which purchase offer the presenter shows for an audience output's trial (PRO-03).
public enum AudienceTrialOffer: Sendable, Equatable {
    /// The output started while Pro is missing; offered once per session.
    case started
    /// The 3 minutes are over; offered once per session.
    case ended
}

/// The trial of one audience output (PRO-03, ADR 0020): the Mac presentation window of one
/// document, or the external display (cable or AirPlay) of the iPad or iPhone.
///
/// It owns the `TrialCoordinator` of the current session and the task that ends it in time,
/// and tells the presenter which purchase offer to show, once per session each.
///
/// - The Mac starts a new session with `start(status:)` whenever the user starts the
///   presentation, and ends it with `stop()` when the user closes the window. Reopening the
///   window after a screen change keeps the session.
/// - iPadOS reports its external-display scenes with `connect(_:status:)` and
///   `disconnect(_:)`. A session lasts while any scene is connected; iPadOS 27 swaps scenes
///   on every window switch, and a scene that connects again within `reconnectGrace` of the
///   last one leaving continues the session. Only a later connection starts a new trial.
@MainActor
@Observable
public final class AudienceOutputTrial {
    public typealias Instant = ContinuousClock.Instant

    /// How long after the last display scene left a new one still continues the session.
    /// Covers iPadOS swapping scenes (window switches, briefly mirroring in between); a
    /// display that is plugged in again later starts a new trial.
    public static let reconnectGrace: Duration = .seconds(10)

    /// The current session's trial; `nil` while no session runs.
    public private(set) var coordinator: TrialCoordinator?
    private var startOffered = false
    private var endOffered = false
    /// The offer of a session that ended before the presenter could show it.
    private var keptOffer: AudienceTrialOffer?

    @ObservationIgnored private var connectedOutputs: Set<String> = []
    @ObservationIgnored private var disconnectedAt: Instant?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// Ends the session once the last display scene has been gone for `reconnectGrace`.
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Instant
    @ObservationIgnored private let sleep: @MainActor (Instant) async throws -> Void

    /// - Parameters:
    ///   - now: the clock; tests pass a fake one.
    ///   - sleep: waits until the given instant, passed to each `TrialCoordinator`.
    public init(
        now: @escaping () -> Instant = { ContinuousClock.now },
        sleep: @escaping @MainActor (Instant) async throws -> Void = { try await Task.sleep(until: $0, clock: .continuous) }
    ) {
        self.now = now
        self.sleep = sleep
    }

    isolated deinit {
        runTask?.cancel()
        graceTask?.cancel()
    }

    public var phase: TrialPhase? { coordinator?.phase }

    /// Whether the audience screen shows the "SlidePilot – Trial Version" banner.
    public var showsBanner: Bool { coordinator?.showsBanner ?? false }

    /// Whether the audience screen hides the deck (with its pointer, drawing and curtain)
    /// because the trial is over.
    public var hidesOutput: Bool { phase == .ended }

    /// The offer the presenter should show now, if any. The end wins over the start; each is
    /// shown once per session (`offerShown(_:)`). The start offer waits until the status is
    /// known to be locked, so a Pro user never sees it. After `stop(keepingPendingOffer:)`
    /// this is the offer that session still owed.
    public var pendingOffer: AudienceTrialOffer? {
        guard let session = coordinator?.session else { return keptOffer }
        switch session.phase {
        case .ended: return endOffered ? nil : .ended
        case .running: return !startOffered && session.status.showsTrialHint ? .started : nil
        case .unlimited: return nil
        }
    }

    /// Records that the presenter showed `offer`. Showing the end also covers the start.
    public func offerShown(_ offer: AudienceTrialOffer) {
        keptOffer = nil
        switch offer {
        case .started:
            startOffered = true
        case .ended:
            startOffered = true
            endOffered = true
        }
    }

    /// Starts a new session, replacing the current one (Mac: the user starts the presentation).
    public func start(status: ProStatus) {
        runTask?.cancel()
        let coordinator = TrialCoordinator(feature: .audienceOutput, status: status, now: now, sleep: sleep)
        self.coordinator = coordinator
        startOffered = false
        endOffered = false
        keptOffer = nil
        disconnectedAt = nil
        runTask = Task { await coordinator.run() }
    }

    /// Ends the session (Mac: the user closed the presentation window).
    ///
    /// - Parameter keepingPendingOffer: keeps an offer the presenter could not show yet,
    ///   until it is shown or a new session starts. The Mac passes `true`: on a single
    ///   screen the presenter is hidden behind the full-screen presentation and only comes
    ///   back when that closes.
    public func stop(keepingPendingOffer: Bool = false) {
        keptOffer = keepingPendingOffer ? pendingOffer : nil
        runTask?.cancel()
        runTask = nil
        graceTask?.cancel()
        graceTask = nil
        coordinator = nil
        connectedOutputs = []
        disconnectedAt = nil
    }

    /// An external-display scene connected. Starts a new session unless another scene is
    /// still connected or the last one left less than `reconnectGrace` ago.
    public func connect(_ output: String, status: ProStatus) {
        let continues = !connectedOutputs.isEmpty
            || (coordinator != nil && disconnectedAt.map { $0.duration(to: now()) < Self.reconnectGrace } == true)
        if !continues {
            start(status: status)
        }
        connectedOutputs.insert(output)
        disconnectedAt = nil
        graceTask?.cancel()
        graceTask = nil
    }

    /// An external-display scene disconnected. The session stays for `reconnectGrace`, so a
    /// scene swap does not start a new trial; its clock keeps running meanwhile.
    public func disconnect(_ output: String) {
        guard connectedOutputs.remove(output) != nil, connectedOutputs.isEmpty else { return }
        let disconnectedAt = now()
        self.disconnectedAt = disconnectedAt
        // Without a display the session ends once the grace is over, so no offer appears for
        // an output that is gone.
        graceTask?.cancel()
        let sleep = self.sleep
        graceTask = Task { [weak self] in
            try? await sleep(disconnectedAt + Self.reconnectGrace)
            guard !Task.isCancelled, let self, self.connectedOutputs.isEmpty else { return }
            self.stop()
        }
    }

    /// Call whenever the app's Pro status changes; buying Pro lifts the limit at once.
    public func statusChanged(_ status: ProStatus) {
        if status.unlocksEverything {
            keptOffer = nil
        }
        coordinator?.statusChanged(status)
    }
}
