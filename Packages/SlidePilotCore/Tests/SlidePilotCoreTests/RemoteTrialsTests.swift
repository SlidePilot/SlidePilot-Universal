import SlidePilotCore
import Testing

@Suite
struct RemoteTrialBookTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    private func hostBook(_ status: ProStatus = .locked) -> RemoteTrialBook<String> {
        RemoteTrialBook(reconnects: .within(RemoteTrialBook<String>.hostReconnectGap), status: status)
    }

    private func controllerBook(_ status: ProStatus = .locked) -> RemoteTrialBook<String> {
        RemoteTrialBook(reconnects: .untilStartedOver, status: status)
    }

    // PRO-04: Pro (or the free Mac download) has no trial.
    @Test(arguments: [ProStatus.unlocked, .unlimited])
    func unlockedConnectionsAreUnlimited(_ status: ProStatus) {
        var book = hostBook(status)
        #expect(book.connectionOpened(by: "iPhone", at: at(0)) == .unlimited)
        #expect(book.phase(of: "iPhone") == nil)
        #expect(book.nextEnd == nil)
        #expect(book.check(at: at(10_000)).isEmpty)
    }

    // PRO-04: an unknown status limits like a locked one (PRO-01).
    @Test(arguments: [ProStatus.locked, .unknown])
    func firstConnectionStartsTrial(_ status: ProStatus) {
        var book = hostBook(status)
        #expect(book.connectionOpened(by: "iPhone", at: at(0)) == .newTrial)
        #expect(book.phase(of: "iPhone") == .running)
        #expect(book.nextEnd != nil)
    }

    // PRO-04: the connection closes after 3 minutes.
    @Test func trialEndsAfterThreeMinutesAndIsReportedOnce() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        #expect(book.nextEnd == at(180))
        #expect(book.check(at: at(179)).isEmpty)
        #expect(book.check(at: at(180)) == ["iPhone"])
        #expect(book.check(at: at(181)).isEmpty)
        #expect(book.phase(of: "iPhone") == .ended)
        #expect(book.nextEnd == nil)
    }

    @Test func eachPeerHasItsOwnTrial() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        #expect(book.connectionOpened(by: "iPad", at: at(60)) == .newTrial)
        #expect(book.nextEnd == at(180))
        #expect(book.check(at: at(180)) == ["iPhone"])
        #expect(book.nextEnd == at(240))
        #expect(book.check(at: at(240)) == ["iPad"])
    }

    // PRO-04: an automatic reconnect continues the trial; it does not start a new one.
    @Test func hostReconnectWithinGapContinues() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        book.connectionClosed(by: "iPhone", at: at(100))
        #expect(book.connectionOpened(by: "iPhone", at: at(110)) == .continued)
        #expect(book.nextEnd == at(180))
    }

    // PRO-04: after the end, the remote's retries are refused and keep the end in place.
    @Test func hostRefusesRetriesAfterEnd() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.check(at: at(180))
        book.connectionClosed(by: "iPhone", at: at(180))
        for second in stride(from: 182.0, through: 300, by: 2) {
            #expect(book.connectionOpened(by: "iPhone", at: at(second)) == .refused)
        }
    }

    // PRO-04: connecting again after a pause starts a new trial.
    @Test func hostStartsNewTrialAfterPause() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.check(at: at(180))
        book.connectionClosed(by: "iPhone", at: at(180))
        #expect(book.connectionOpened(by: "iPhone", at: at(185)) == .refused)
        #expect(book.connectionOpened(by: "iPhone", at: at(196)) == .newTrial)
        #expect(book.nextEnd == at(376))
    }

    // PRO-04: a running trial is never shortened or restarted by a pause (e.g. a locked
    // iPhone whose remote reconnects when it wakes).
    @Test func hostContinuesRunningTrialAfterLongPause() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        book.connectionClosed(by: "iPhone", at: at(30))
        #expect(book.connectionOpened(by: "iPhone", at: at(150)) == .continued)
        #expect(book.nextEnd == at(180))
    }

    @Test func hostRefusesAfterEndReachedWhileAway() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        book.connectionClosed(by: "iPhone", at: at(30))
        #expect(book.check(at: at(180)) == ["iPhone"])
        #expect(book.connectionOpened(by: "iPhone", at: at(185)) == .refused)
        // Seen after the end: a pause after that attempt counts as connecting again.
        #expect(book.connectionOpened(by: "iPhone", at: at(194)) == .refused)
        #expect(book.connectionOpened(by: "iPhone", at: at(205)) == .newTrial)
    }

    @Test func hostRefusesRemoteThatWasAwayLongAtTheEnd() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        book.connectionClosed(by: "iPhone", at: at(100))
        _ = book.check(at: at(180))
        #expect(book.connectionOpened(by: "iPhone", at: at(3_600)) == .refused)
    }

    // A lifted trial is forgotten after a pause, like an ended one.
    @Test func hostForgetsLiftedTrialAfterPause() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.update(status: .unlocked, at: at(10))
        book.connectionClosed(by: "iPhone", at: at(20))
        _ = book.update(status: .locked, at: at(25))
        #expect(book.connectionOpened(by: "iPhone", at: at(40)) == .newTrial)
    }

    // An open connection never expires, however long it lasts.
    @Test func hostKeepsPeerWithOpenConnection() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        #expect(book.connectionOpened(by: "iPhone", at: at(150)) == .continued)
        book.connectionClosed(by: "iPhone", at: at(160))
        #expect(book.check(at: at(180)) == ["iPhone"])
        #expect(book.phase(of: "iPhone") == .ended)
    }

    // A trial that ends while the remote is away is reported, so a reconnecting remote stops.
    @Test func trialEndingWithoutConnectionIsReported() {
        var book = controllerBook()
        _ = book.connectionOpened(by: "Mac", at: at(0))
        book.connectionClosed(by: "Mac", at: at(60))
        #expect(book.check(at: at(180)) == ["Mac"])
    }

    // While the host cannot be reached (app in the background), the remote's pause does not count.
    @Test func hostUnreachableTimeDoesNotCountAsPause() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.check(at: at(180))
        book.connectionClosed(by: "iPhone", at: at(180))
        book.becameReachable(at: at(600))
        #expect(book.connectionOpened(by: "iPhone", at: at(605)) == .refused)
    }

    // PRO-04: the controller's retries never start a new trial, however long they take.
    @Test func controllerReconnectContinuesAfterAnyPause() {
        var book = controllerBook()
        _ = book.connectionOpened(by: "Mac", at: at(0))
        book.connectionClosed(by: "Mac", at: at(10))
        #expect(book.connectionOpened(by: "Mac", at: at(170)) == .continued)
        _ = book.check(at: at(180))
        book.connectionClosed(by: "Mac", at: at(180))
        #expect(book.connectionOpened(by: "Mac", at: at(900)) == .refused)
    }

    // PRO-04: connecting again (the user picks the device) starts a new trial.
    @Test func controllerStartOverStartsNewTrial() {
        var book = controllerBook()
        _ = book.connectionOpened(by: "Mac", at: at(0))
        _ = book.check(at: at(180))
        book.startOver(with: "Mac")
        #expect(book.phase(of: "Mac") == nil)
        #expect(book.connectionOpened(by: "Mac", at: at(181)) == .newTrial)
    }

    // PRO-04: buying Pro during the trial lifts the limit at once.
    @Test func unlockingLiftsRunningTrials() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        #expect(book.update(status: .unlocked, at: at(60)).isEmpty)
        #expect(book.phase(of: "iPhone") == .unlimited)
        #expect(book.nextEnd == nil)
        #expect(book.check(at: at(1_000)).isEmpty)
        #expect(book.connectionOpened(by: "iPhone", at: at(1_000)) == .unlimited)
    }

    @Test func unlockingAfterEndAdmitsAgain() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.check(at: at(180))
        _ = book.update(status: .unlocked, at: at(185))
        #expect(book.connectionOpened(by: "iPhone", at: at(186)) == .unlimited)
    }

    // PRO-01: a lifted limit stays lifted for that session, also if the status locks again.
    @Test func liftedTrialStaysLifted() {
        var book = hostBook()
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        _ = book.update(status: .unlocked, at: at(60))
        #expect(book.update(status: .locked, at: at(500)).isEmpty)
        #expect(book.connectionOpened(by: "iPhone", at: at(501)) == .unlimited)
        #expect(book.connectionOpened(by: "iPad", at: at(501)) == .newTrial)
    }

    // PRO-01: an unknown status waits for StoreKit at most 30 seconds past 3:00.
    @Test func unknownStatusEndsAfterGrace() {
        var book = hostBook(.unknown)
        _ = book.connectionOpened(by: "iPhone", at: at(0))
        #expect(book.nextEnd == at(210))
        #expect(book.check(at: at(200)).isEmpty)
        #expect(book.update(status: .locked, at: at(200)) == ["iPhone"])
    }
}

/// A clock the tests move by hand.
@MainActor
private final class RemoteFakeClock {
    var now: ContinuousClock.Instant
    let slept: AsyncStream<ContinuousClock.Instant>
    private let continuation: AsyncStream<ContinuousClock.Instant>.Continuation

    init(_ now: ContinuousClock.Instant) {
        self.now = now
        (slept, continuation) = AsyncStream.makeStream()
    }

    /// Reports the wait and waits until cancelled (woken), like a long real sleep.
    func sleep(until instant: ContinuousClock.Instant) async throws {
        continuation.yield(instant)
        try await Task.sleep(for: .seconds(3_600))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RemoteTrialsTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    @Test func runWaitsForTheEndAndReportsIt() async {
        let clock = RemoteFakeClock(start)
        let trials = RemoteTrials<String>(
            reconnects: .untilStartedOver,
            status: .locked,
            now: { clock.now },
            sleep: { try await clock.sleep(until: $0) }
        )
        var slept = clock.slept.makeAsyncIterator()
        let (reports, reported) = AsyncStream<[String]>.makeStream()
        let task = Task { await trials.run { reported.yield($0) } }
        defer { task.cancel() }

        #expect(trials.connectionOpened(by: "Mac") == .newTrial)
        // Woken by the new trial, it waits for its end.
        #expect(await slept.next() == at(180))
        clock.now = at(180)
        trials.statusChanged(.locked)
        var ends = reports.makeAsyncIterator()
        #expect(await ends.next() == ["Mac"])
    }

    // PRO-04: buying Pro during the trial lifts the limit at once; nothing is reported.
    @Test func unlockStopsWaiting() async {
        let clock = RemoteFakeClock(start)
        let trials = RemoteTrials<String>(
            reconnects: .untilStartedOver,
            status: .locked,
            now: { clock.now },
            sleep: { try await clock.sleep(until: $0) }
        )
        var slept = clock.slept.makeAsyncIterator()
        let task = Task { await trials.run { _ in Issue.record("No trial should end") } }
        defer { task.cancel() }

        _ = trials.connectionOpened(by: "Mac")
        #expect(await slept.next() == at(180))
        trials.statusChanged(.unlocked)
        clock.now = at(500)
        trials.statusChanged(.unlocked)
        #expect(trials.book.phase(of: "Mac") == .unlimited)
        #expect(trials.book.nextEnd == nil)
    }
}
