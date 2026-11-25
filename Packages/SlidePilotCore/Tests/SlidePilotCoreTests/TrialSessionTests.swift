import SlidePilotCore
import Testing

@Suite
struct TrialSessionTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    private func lockedSession(_ feature: LimitedFeature = .audienceOutput) -> TrialSession {
        TrialSession(feature: feature, status: .locked, at: at(0))
    }

    // PRO-01: a trial lasts 3 minutes.
    @Test func limitIsThreeMinutes() {
        #expect(TrialSession.limit == .seconds(180))
    }

    @Test(arguments: LimitedFeature.allCases)
    func lockedSessionStartsRunningWithBanner(_ feature: LimitedFeature) {
        let session = lockedSession(feature)
        #expect(session.feature == feature)
        #expect(session.startedAt == at(0))
        #expect(session.phase == .running)
        #expect(session.showsBanner)
        #expect(session.deadline == at(180))
        #expect(session.remainingTime(at: at(0)) == .seconds(180))
        #expect(session.remainingTime(at: at(61.5)) == .seconds(118.5))
    }

    @Test func runsUntilJustBeforeThreeMinutes() {
        var session = lockedSession()
        session.update(status: .locked, at: at(179.999))
        #expect(session.phase == .running)
        #expect(session.remainingTime(at: at(179.999))! > .zero)
    }

    // PRO-01: the trial ends at exactly 3:00.
    @Test func endsAtExactlyThreeMinutes() {
        var session = lockedSession()
        session.update(status: .locked, at: at(180))
        #expect(session.phase == .ended)
        #expect(!session.showsBanner)
        #expect(session.deadline == nil)
        #expect(session.remainingTime(at: at(180)) == nil)
    }

    @Test func endsWhenFirstCheckedLate() {
        var session = lockedSession()
        session.update(status: .locked, at: at(3_600))
        #expect(session.phase == .ended)
    }

    // PRO-01: the end is final; time going on (or back) never restarts the trial.
    @Test func endedStaysEnded() {
        var session = lockedSession()
        session.update(status: .locked, at: at(180))
        session.update(status: .locked, at: at(10_000))
        session.update(status: .locked, at: at(5))
        session.update(status: .unknown, at: at(5))
        session.update(status: .locked, at: at(5))
        #expect(session.phase == .ended)
        #expect(session.remainingTime(at: at(5)) == nil)
    }

    // PRO-01: a new trial needs a new session (a new connection).
    @Test func newSessionStartsNewTrial() {
        var first = lockedSession()
        first.update(status: .locked, at: at(200))
        let second = TrialSession(feature: .audienceOutput, status: .locked, at: at(200))
        #expect(first.phase == .ended)
        #expect(second.phase == .running)
        #expect(second.deadline == at(380))
    }

    // PRO-01: buying Pro during a trial lifts the limit at once.
    @Test func unlockingMidTrialLiftsLimit() {
        var session = lockedSession()
        session.update(status: .unlocked, at: at(90))
        #expect(session.phase == .unlimited)
        #expect(!session.showsBanner)
        #expect(session.deadline == nil)
        #expect(session.remainingTime(at: at(90)) == nil)
        session.update(status: .unlocked, at: at(10_000))
        #expect(session.phase == .unlimited)
    }

    // Buying Pro from the "Trial Ended" offer brings the output back without reconnecting.
    @Test func unlockingAfterEndLiftsLimit() {
        var session = lockedSession()
        session.update(status: .locked, at: at(180))
        session.update(status: .unlocked, at: at(240))
        #expect(session.phase == .unlimited)
    }

    // A lifted limit stays lifted for this session, even if the status drops again.
    @Test func liftedLimitStaysLifted() {
        var session = lockedSession()
        session.update(status: .unlocked, at: at(10))
        session.update(status: .locked, at: at(500))
        #expect(session.phase == .unlimited)
    }

    @Test(arguments: [ProStatus.unlocked, .unlimited])
    func unlockedStatusStartsUnlimited(_ status: ProStatus) {
        var session = TrialSession(feature: .remoteControl, status: status, at: at(0))
        #expect(session.phase == .unlimited)
        #expect(!session.showsBanner)
        session.update(status: status, at: at(10_000))
        #expect(session.phase == .unlimited)
    }

    // ADR 0020: the free Mac download is never limited.
    @Test(arguments: LimitedFeature.allCases)
    func freeDownloadNeverLimited(_ feature: LimitedFeature) {
        var session = TrialSession(feature: feature, status: .unlimited, at: at(0))
        for seconds in [0.0, 179, 180, 181, 86_400] {
            session.update(status: .unlimited, at: at(seconds))
            #expect(session.phase == .unlimited)
        }
    }

    // An unknown status limits (the clock runs) but shows neither the banner nor, within the
    // grace period, the end.
    @Test func unknownRunsWithoutBannerAndWaitsForStatus() {
        var session = TrialSession(feature: .audienceOutput, status: .unknown, at: at(0))
        #expect(session.phase == .running)
        #expect(!session.showsBanner)
        #expect(session.remainingTime(at: at(30)) == .seconds(150))
        #expect(session.latestEnd == at(210))
        session.update(status: .unknown, at: at(209.999))
        #expect(session.phase == .running)
        #expect(session.remainingTime(at: at(200)) == .zero)
    }

    // A status check that never answers cannot lift the limit: the end comes after the grace.
    @Test func unknownEndsAfterGrace() {
        #expect(TrialSession.unknownStatusGrace == .seconds(30))
        var session = TrialSession(feature: .remoteControl, status: .unknown, at: at(0))
        session.update(status: .unknown, at: at(210))
        #expect(session.phase == .ended)
    }

    @Test func unknownPastDeadlineEndsOnceLocked() {
        var session = TrialSession(feature: .audienceOutput, status: .unknown, at: at(0))
        session.update(status: .unknown, at: at(200))
        #expect(session.latestEnd == at(210))
        session.update(status: .locked, at: at(201))
        #expect(session.phase == .ended)
    }

    @Test func unknownPastDeadlineLiftedOnceUnlocked() {
        var session = TrialSession(feature: .audienceOutput, status: .unknown, at: at(0))
        session.update(status: .unknown, at: at(200))
        session.update(status: .unlocked, at: at(201))
        #expect(session.phase == .unlimited)
    }

    // The time before the status is known counts toward the 3 minutes.
    @Test func unknownTimeCountsTowardTrial() {
        var session = TrialSession(feature: .audienceOutput, status: .unknown, at: at(0))
        session.update(status: .locked, at: at(60))
        #expect(session.showsBanner)
        #expect(session.latestEnd == at(180))
        #expect(session.remainingTime(at: at(60)) == .seconds(120))
        session.update(status: .locked, at: at(180))
        #expect(session.phase == .ended)
    }
}

/// A clock the tests move by hand.
@MainActor
private final class FakeClock {
    var now: ContinuousClock.Instant
    var sleptUntil: [ContinuousClock.Instant] = []

    init(_ now: ContinuousClock.Instant) {
        self.now = now
    }

    func sleep(until instant: ContinuousClock.Instant) {
        sleptUntil.append(instant)
        now = instant
    }
}

/// A sleep that reports every call and only ends when cancelled (woken).
@MainActor
private final class WaitingSleeper {
    private(set) var calls: [ContinuousClock.Instant] = []
    let started: AsyncStream<ContinuousClock.Instant>
    private let continuation: AsyncStream<ContinuousClock.Instant>.Continuation

    init() {
        (started, continuation) = AsyncStream.makeStream()
    }

    func sleep(until instant: ContinuousClock.Instant) async throws {
        calls.append(instant)
        continuation.yield(instant)
        try await Task.sleep(for: .seconds(3_600))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TrialCoordinatorTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    private func coordinator(status: ProStatus, clock: FakeClock) -> TrialCoordinator {
        TrialCoordinator(
            feature: .remoteControl,
            status: status,
            now: { clock.now },
            sleep: { clock.sleep(until: $0) }
        )
    }

    /// A coordinator whose wait only ends when cancelled.
    private func waitingCoordinator(status: ProStatus, sleeper: WaitingSleeper) -> TrialCoordinator {
        TrialCoordinator(
            feature: .audienceOutput,
            status: status,
            now: { [start] in start },
            sleep: { try await sleeper.sleep(until: $0) }
        )
    }

    @Test func readsTheInjectedClock() {
        let clock = FakeClock(start)
        let trial = coordinator(status: .locked, clock: clock)
        #expect(trial.session.startedAt == start)
        #expect(trial.session.feature == .remoteControl)
        clock.now = at(45)
        #expect(trial.remainingTime() == .seconds(135))
        #expect(trial.session.deadline == at(180))
        #expect(trial.showsBanner)
    }

    @Test func refreshEndsAtDeadline() {
        let clock = FakeClock(start)
        let trial = coordinator(status: .locked, clock: clock)
        clock.now = at(179)
        trial.refresh()
        #expect(trial.phase == .running)
        clock.now = at(180)
        trial.refresh()
        #expect(trial.phase == .ended)
    }

    @Test func statusChangeLiftsLimit() {
        let clock = FakeClock(start)
        let trial = coordinator(status: .locked, clock: clock)
        clock.now = at(100)
        trial.statusChanged(.unlocked)
        #expect(trial.phase == .unlimited)
        #expect(!trial.showsBanner)
        #expect(trial.remainingTime() == nil)
    }

    @Test func runSleepsUntilDeadlineAndEnds() async {
        let clock = FakeClock(start)
        let trial = coordinator(status: .locked, clock: clock)
        clock.now = at(30)
        await trial.run()
        #expect(clock.sleptUntil == [at(180)])
        #expect(trial.phase == .ended)
    }

    @Test func runReturnsAtOnceWhenUnlimited() async {
        let clock = FakeClock(start)
        let trial = coordinator(status: .unlimited, clock: clock)
        await trial.run()
        #expect(clock.sleptUntil.isEmpty)
        #expect(trial.phase == .unlimited)
    }

    // With an unknown status that never resolves, run() ends the trial after the grace.
    @Test func runEndsUnknownStatusAfterGrace() async {
        let clock = FakeClock(start)
        let trial = coordinator(status: .unknown, clock: clock)
        await trial.run()
        #expect(clock.sleptUntil == [at(210)])
        #expect(trial.phase == .ended)
    }

    // Buying Pro wakes a waiting run() at once instead of at the deadline.
    @Test func statusChangeWakesRun() async {
        let sleeper = WaitingSleeper()
        var started = sleeper.started.makeAsyncIterator()
        let trial = waitingCoordinator(status: .locked, sleeper: sleeper)
        let task = Task { await trial.run() }
        #expect(await started.next() == at(180))
        trial.statusChanged(.unlocked)
        await task.value
        #expect(trial.phase == .unlimited)
        #expect(sleeper.calls.count == 1)
    }

    // A known locked status wakes run() and sends it back to wait for the earlier deadline.
    @Test func lockedStatusChangeMovesWaitToDeadline() async {
        let sleeper = WaitingSleeper()
        var started = sleeper.started.makeAsyncIterator()
        let trial = waitingCoordinator(status: .unknown, sleeper: sleeper)
        let task = Task { await trial.run() }
        #expect(await started.next() == at(210))
        trial.statusChanged(.locked)
        #expect(await started.next() == at(180))
        #expect(trial.phase == .running)
        task.cancel()
        await task.value
        #expect(trial.phase == .running)
    }

    // Cancelling the owning task (SwiftUI's .task) ends run() without ending the trial.
    @Test func cancellingTaskStopsRun() async {
        let sleeper = WaitingSleeper()
        var started = sleeper.started.makeAsyncIterator()
        let trial = waitingCoordinator(status: .locked, sleeper: sleeper)
        let task = Task { await trial.run() }
        _ = await started.next()
        task.cancel()
        await task.value
        #expect(trial.phase == .running)
        #expect(trial.showsBanner)
        #expect(sleeper.calls.count == 1)
    }

    // A restarted .task overlapping the old run(): status changes still wake the new one.
    @Test func overlappingRunStaysWakeable() async {
        let sleeper = WaitingSleeper()
        var started = sleeper.started.makeAsyncIterator()
        let trial = waitingCoordinator(status: .locked, sleeper: sleeper)
        let first = Task { await trial.run() }
        _ = await started.next()
        first.cancel()
        let second = Task { await trial.run() }
        _ = await started.next()
        await first.value
        trial.statusChanged(.unlocked)
        await second.value
        #expect(trial.phase == .unlimited)
    }
}
