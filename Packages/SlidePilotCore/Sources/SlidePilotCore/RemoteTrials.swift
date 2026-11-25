/// The trials of the remote connections on one side of the remote (PRO-04, ADR 0020): which
/// connection starts a new 3-minute trial, which one continues a running trial, and which one
/// must close because its trial has ended.
///
/// A trial belongs to the other device (`Peer`), not to one network connection: the remote
/// reconnects on its own when a connection drops (REM-02), and those automatic reconnects
/// continue the trial instead of starting a new one. Only connecting again starts a new trial.
/// The remote protocol carries no Pro status (ADR 0017), so each side keeps its own book.
public struct RemoteTrialBook<Peer: Hashable & Sendable>: Sendable {
    public typealias Instant = ContinuousClock.Instant

    /// How this side tells an automatic reconnect from connecting again.
    public enum Reconnects: Sendable, Equatable {
        /// The controller: the app knows when the user connects again and calls `startOver(with:)`;
        /// every other connection to that device continues its trial.
        case untilStartedOver
        /// The host: it cannot see why a controller connects. Every connection while the
        /// peer's trial runs continues it. Once it has ended, connections are refused until
        /// the peer paused for longer than `gap`: the remote retries every few seconds while it
        /// wants to reconnect, so a longer pause means the user left and connects again.
        case within(Duration)
    }

    /// What happens with a verified connection.
    public enum Admission: Sendable, Equatable {
        /// Pro is unlocked (or this is the free Mac download): no trial.
        case unlimited
        /// A new trial started; the purchase offer may show.
        case newTrial
        /// An automatic reconnect: the running trial continues.
        case continued
        /// The trial of this device has ended: close the connection.
        case refused
    }

    /// The host's gap: well above the remote's 2-second retry interval and the time a
    /// reconnect takes, short enough that leaving and connecting again is not refused for long.
    public static var hostReconnectGap: Duration { .seconds(10) }

    struct Record: Sendable, Equatable {
        var session: TrialSession
        /// Admitted connections that are still open.
        var connections: Int
        /// The last connection, close or refused attempt of the peer.
        var lastSeen: Instant
        var isEndReported = false
        /// Whether the peer was connected at the end or tried to connect since; until then an
        /// ended trial is kept, so a remote that was away (e.g. a locked iPhone) is refused when
        /// it comes back instead of starting a new trial.
        var wasSeenAfterEnd = false
    }

    public let reconnects: Reconnects
    public private(set) var status: ProStatus
    private var records: [Peer: Record] = [:]

    public init(reconnects: Reconnects, status: ProStatus) {
        self.reconnects = reconnects
        self.status = status
    }

    /// The phase of the peer's trial; `nil` if it has none (none started, or forgotten).
    public func phase(of peer: Peer) -> TrialPhase? {
        records[peer]?.session.phase
    }

    /// When the next running trial ends at the latest; `nil` if none runs.
    public var nextEnd: Instant? {
        records.values.compactMap(\.session.latestEnd).min()
    }

    /// A connection with `peer` was verified. Call `connectionClosed(by:at:)` when a connection
    /// admitted with `newTrial` or `continued` closes.
    public mutating func connectionOpened(by peer: Peer, at now: Instant) -> Admission {
        forgetExpired(at: now)
        guard var record = records[peer] else {
            guard status.limits(.remoteControl) else { return .unlimited }
            records[peer] = Record(
                session: TrialSession(feature: .remoteControl, status: status, at: now),
                connections: 1,
                lastSeen: now
            )
            return .newTrial
        }
        record.session.update(status: status, at: now)
        record.lastSeen = now
        let admission: Admission
        switch record.session.phase {
        case .ended:
            record.wasSeenAfterEnd = true
            admission = .refused
        case .running:
            record.connections += 1
            admission = .continued
        case .unlimited:
            // A lifted limit stays lifted for this trial session (PRO-01).
            record.connections += 1
            admission = .unlimited
        }
        records[peer] = record
        return admission
    }

    /// An admitted connection with `peer` closed.
    public mutating func connectionClosed(by peer: Peer, at now: Instant) {
        guard var record = records[peer] else { return }
        record.connections = max(0, record.connections - 1)
        record.lastSeen = now
        records[peer] = record
    }

    /// The user connects to `peer` again (controller): its next connection starts a new trial.
    public mutating func startOver(with peer: Peer) {
        records[peer] = nil
    }

    /// This device can be reached again, e.g. the host advertises again after the app was in
    /// the background. The time it could not be reached does not count as a pause of the peers.
    public mutating func becameReachable(at now: Instant) {
        for peer in Array(records.keys) {
            guard var record = records[peer], record.connections == 0 else { continue }
            record.lastSeen = max(record.lastSeen, now)
            records[peer] = record
        }
    }

    /// Applies a new Pro status; returns the peers whose trial ended now.
    public mutating func update(status: ProStatus, at now: Instant) -> [Peer] {
        self.status = status
        return check(at: now)
    }

    /// Re-evaluates every trial against the clock; returns the peers whose trial ended now,
    /// each only once. Their connections must close; a peer without an open connection is
    /// returned too, so a controller that is still reconnecting stops.
    public mutating func check(at now: Instant) -> [Peer] {
        var ended: [Peer] = []
        for peer in Array(records.keys) {
            guard var record = records[peer] else { continue }
            record.session.update(status: status, at: now)
            if record.session.phase == .ended, !record.isEndReported {
                record.isEndReported = true
                if record.connections > 0 {
                    record.wasSeenAfterEnd = true
                    record.lastSeen = now
                }
                ended.append(peer)
            }
            records[peer] = record
        }
        forgetExpired(at: now)
        return ended
    }

    /// Host: forgets the peers whose trial is over (ended or lifted) and that paused longer
    /// than the gap, so their next connection is a new one. A running trial is kept until it
    /// ends, however long the peer is away (e.g. a locked iPhone), so no pause restarts it; an
    /// ended one until the peer was seen after the end.
    private mutating func forgetExpired(at now: Instant) {
        guard case .within(let gap) = reconnects else { return }
        records = records.filter { _, record in
            let isOver: Bool = switch record.session.phase {
            case .running: false
            case .ended: record.wasSeenAfterEnd
            case .unlimited: true
            }
            return !isOver || record.connections > 0 || now <= record.lastSeen + gap
        }
    }
}

/// Runs a `RemoteTrialBook` for the app (PRO-04): reads the clock and reports the trials that
/// end, in time.
@MainActor
public final class RemoteTrials<Peer: Hashable & Sendable> {
    public typealias Instant = ContinuousClock.Instant

    public private(set) var book: RemoteTrialBook<Peer>

    private let now: () -> Instant
    private let sleep: @MainActor (Instant) async throws -> Void
    /// The pending wait of `run(onEnded:)`; cancelled to wake it after a change.
    private var wakeUp: Task<Void, Never>?

    /// - Parameters:
    ///   - now: the clock; tests pass a fake one.
    ///   - sleep: waits until the given instant; throws when cancelled.
    public init(
        reconnects: RemoteTrialBook<Peer>.Reconnects,
        status: ProStatus,
        now: @escaping () -> Instant = { ContinuousClock.now },
        sleep: @escaping @MainActor (Instant) async throws -> Void = { try await Task.sleep(until: $0, clock: .continuous) }
    ) {
        self.book = RemoteTrialBook(reconnects: reconnects, status: status)
        self.now = now
        self.sleep = sleep
    }

    public func connectionOpened(by peer: Peer) -> RemoteTrialBook<Peer>.Admission {
        let admission = book.connectionOpened(by: peer, at: now())
        if admission == .newTrial { wake() }
        return admission
    }

    public func connectionClosed(by peer: Peer) {
        book.connectionClosed(by: peer, at: now())
    }

    public func startOver(with peer: Peer) {
        book.startOver(with: peer)
    }

    public func becameReachable() {
        book.becameReachable(at: now())
    }

    /// Call whenever the app's Pro status changes; `run(onEnded:)` reports trials it ended.
    public func statusChanged(_ status: ProStatus) {
        let ended = book.update(status: status, at: now())
        pendingEnds.append(contentsOf: ended)
        wake()
    }

    /// Ends found outside `run(onEnded:)`, reported by it.
    private var pendingEnds: [Peer] = []

    private func wake() {
        wakeUp?.cancel()
    }

    /// Reports the peers whose trial ends, as they end, until the calling task is cancelled.
    /// Run it once, in a task owned by the remote service or the remote mode window.
    /// `onEnded` must not change the Pro status; ends that causes would wait for the next wake.
    public func run(onEnded: @MainActor ([Peer]) -> Void) async {
        while !Task.isCancelled {
            let ended = pendingEnds + book.check(at: now())
            pendingEnds = []
            if !ended.isEmpty { onEnded(ended) }
            let sleep = self.sleep
            let end = book.nextEnd
            // Without a running trial it waits until a change wakes it.
            let wait = Task {
                if let end {
                    _ = try? await sleep(end)
                } else {
                    _ = try? await Task.sleep(for: .seconds(86_400))
                }
            }
            wakeUp?.cancel()
            wakeUp = wait
            await withTaskCancellationHandler {
                await wait.value
            } onCancel: {
                wait.cancel()
            }
            if wakeUp == wait { wakeUp = nil }
        }
    }
}
