import SlidePilotCore
import Testing

/// A clock the tests move by hand; its sleep waits until cancelled, so only `refresh()`
/// moves a trial forward, unless `jumps` lets the sleep reach its deadline at once.
@MainActor
private final class ManualClock {
    let start = ContinuousClock.now
    var now: ContinuousClock.Instant
    var jumps = false

    init() {
        now = start
    }

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    func advance(to seconds: Double) {
        now = at(seconds)
    }

    func sleep(until instant: ContinuousClock.Instant) async throws {
        if jumps {
            now = instant
            return
        }
        try await Task.sleep(for: .seconds(3_600))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AudienceOutputTrialTests {
    private let clock = ManualClock()

    private func trial() -> AudienceOutputTrial {
        let clock = clock
        return AudienceOutputTrial(now: { clock.now }, sleep: { try await clock.sleep(until: $0) })
    }

    /// Moves the clock and lets the session see it.
    private func advance(_ trial: AudienceOutputTrial, to seconds: Double) {
        clock.advance(to: seconds)
        trial.coordinator?.refresh()
    }

    @Test func noSessionBeforeTheOutputStarts() {
        let trial = trial()
        #expect(trial.coordinator == nil)
        #expect(trial.phase == nil)
        #expect(!trial.showsBanner)
        #expect(!trial.hidesOutput)
        #expect(trial.pendingOffer == nil)
    }

    // PRO-03: the banner shows while the trial runs; the deck disappears at 3:00.
    @Test func lockedTrialShowsBannerThenHidesOutput() {
        let trial = trial()
        trial.start(status: .locked)
        #expect(trial.phase == .running)
        #expect(trial.showsBanner)
        #expect(!trial.hidesOutput)
        advance(trial, to: 180)
        #expect(trial.phase == .ended)
        #expect(!trial.showsBanner)
        #expect(trial.hidesOutput)
    }

    @Test func runTaskEndsTheTrialInTime() async {
        clock.jumps = true
        let trial = trial()
        trial.start(status: .locked)
        for _ in 0..<100 where trial.phase == .running {
            await Task.yield()
        }
        #expect(trial.hidesOutput)
        #expect(clock.now == clock.at(180))
    }

    // PRO-03, ADR 0020: no change for Pro and the free Mac download.
    @Test(arguments: [ProStatus.unlocked, .unlimited])
    func unlockedStatusNeverLimits(_ status: ProStatus) {
        let trial = trial()
        trial.start(status: status)
        advance(trial, to: 600)
        #expect(trial.phase == .unlimited)
        #expect(!trial.showsBanner)
        #expect(!trial.hidesOutput)
        #expect(trial.pendingOffer == nil)
    }

    // PRO-03: buying Pro during the trial lifts the banner and the limit at once, and also
    // after the end.
    @Test(arguments: [0.0, 200.0])
    func buyingProLiftsTheLimit(at seconds: Double) {
        let trial = trial()
        trial.start(status: .locked)
        advance(trial, to: seconds)
        trial.statusChanged(.unlocked)
        #expect(trial.phase == .unlimited)
        #expect(!trial.showsBanner)
        #expect(!trial.hidesOutput)
        #expect(trial.pendingOffer == nil)
    }

    // PRO-03: the start offer once per session, then the end offer once.
    @Test func offersStartOnceThenEndOnce() {
        let trial = trial()
        trial.start(status: .locked)
        #expect(trial.pendingOffer == .started)
        trial.offerShown(.started)
        #expect(trial.pendingOffer == nil)
        advance(trial, to: 180)
        #expect(trial.pendingOffer == .ended)
        trial.offerShown(.ended)
        #expect(trial.pendingOffer == nil)
    }

    @Test func endOfferWinsOverAnUnshownStartOffer() {
        let trial = trial()
        trial.start(status: .locked)
        advance(trial, to: 180)
        #expect(trial.pendingOffer == .ended)
        trial.offerShown(.ended)
        #expect(trial.pendingOffer == nil)
    }

    // PRO-05: no offer while the status is unknown; it comes once StoreKit says locked.
    @Test func startOfferWaitsForAKnownLockedStatus() {
        let trial = trial()
        trial.start(status: .unknown)
        #expect(trial.pendingOffer == nil)
        #expect(!trial.showsBanner)
        trial.statusChanged(.locked)
        #expect(trial.pendingOffer == .started)
        #expect(trial.showsBanner)
    }

    // PRO-03 (Mac): starting the presentation again starts a new trial.
    @Test func startAgainStartsANewTrial() {
        let trial = trial()
        trial.start(status: .locked)
        trial.offerShown(.started)
        advance(trial, to: 180)
        trial.offerShown(.ended)
        let ended = trial.coordinator
        trial.start(status: .locked)
        #expect(trial.coordinator !== ended)
        #expect(trial.phase == .running)
        #expect(trial.pendingOffer == .started)
        advance(trial, to: 359)
        #expect(trial.phase == .running)
        advance(trial, to: 360)
        #expect(trial.phase == .ended)
    }

    @Test func stopEndsTheSession() {
        let trial = trial()
        trial.start(status: .locked)
        trial.stop()
        #expect(trial.coordinator == nil)
        #expect(trial.pendingOffer == nil)
        #expect(!trial.hidesOutput)
    }

    // PRO-03 (iPad, iPhone): connecting the display starts the trial.
    @Test func connectingStartsATrial() {
        let trial = trial()
        trial.connect("a", status: .locked)
        #expect(trial.phase == .running)
        #expect(trial.pendingOffer == .started)
    }

    /// iPadOS 27 connects the next window's scene before the previous one leaves.
    @Test func overlappingScenesKeepTheSession() {
        let trial = trial()
        trial.connect("a", status: .locked)
        let session = trial.coordinator
        advance(trial, to: 100)
        trial.connect("b", status: .locked)
        trial.disconnect("a")
        #expect(trial.coordinator === session)
        advance(trial, to: 180)
        #expect(trial.hidesOutput)
    }

    // ADR 0020: automatic reconnects do not start a new trial.
    @Test func reconnectWithinGraceKeepsTheEndedSession() {
        let trial = trial()
        trial.connect("a", status: .locked)
        advance(trial, to: 180)
        trial.offerShown(.ended)
        trial.disconnect("a")
        advance(trial, to: 189.9)
        trial.connect("b", status: .locked)
        #expect(trial.hidesOutput)
        #expect(trial.pendingOffer == nil)
    }

    // PRO-03: connecting the display again starts a new trial.
    @Test func reconnectAfterGraceStartsANewTrial() {
        let trial = trial()
        trial.connect("a", status: .locked)
        advance(trial, to: 180)
        trial.disconnect("a")
        advance(trial, to: 190)
        trial.connect("a", status: .locked)
        #expect(trial.phase == .running)
        #expect(trial.pendingOffer == .started)
        #expect(trial.coordinator?.session.startedAt == clock.at(190))
    }

    @Test func unknownSceneDisconnectIsIgnored() {
        let trial = trial()
        trial.connect("a", status: .locked)
        trial.disconnect("b")
        advance(trial, to: 600)
        // "a" is still connected, so a new scene continues the session.
        trial.connect("c", status: .locked)
        #expect(trial.hidesOutput)
    }

    // No offer for a display that is gone: the session ends once the grace is over.
    @Test func sessionEndsWhenTheGraceRunsOut() async {
        let trial = trial()
        trial.connect("a", status: .locked)
        // The grace's sleep reaches its deadline at once.
        clock.jumps = true
        trial.disconnect("a")
        for _ in 0..<100 where trial.coordinator != nil {
            await Task.yield()
        }
        #expect(trial.coordinator == nil)
        #expect(trial.pendingOffer == nil)
    }

    // Mac, single screen: the presenter is hidden while presenting, so the offer it could
    // not show survives the end of the session.
    @Test(arguments: [(0.0, AudienceTrialOffer.started), (200.0, AudienceTrialOffer.ended)])
    func stopCanKeepTheOfferNotShownYet(seconds: Double, offer: AudienceTrialOffer) {
        let trial = trial()
        trial.start(status: .locked)
        advance(trial, to: seconds)
        trial.stop(keepingPendingOffer: true)
        #expect(trial.coordinator == nil)
        #expect(trial.pendingOffer == offer)
        trial.offerShown(offer)
        #expect(trial.pendingOffer == nil)
    }

    @Test func stopKeepsNoOfferThatWasShown() {
        let trial = trial()
        trial.start(status: .locked)
        trial.offerShown(.started)
        trial.stop(keepingPendingOffer: true)
        #expect(trial.pendingOffer == nil)
    }

    @Test func stopDropsTheOfferByDefault() {
        let trial = trial()
        trial.start(status: .locked)
        trial.stop()
        #expect(trial.pendingOffer == nil)
    }

    @Test func keptOfferEndsWithANewSessionOrPro() {
        let trial = trial()
        trial.start(status: .locked)
        advance(trial, to: 200)
        trial.stop(keepingPendingOffer: true)
        trial.start(status: .locked)
        #expect(trial.pendingOffer == .started)
        trial.stop(keepingPendingOffer: true)
        trial.statusChanged(.unlocked)
        #expect(trial.pendingOffer == nil)
    }

    @Test func proUserKeepsNoOffer() {
        let trial = trial()
        trial.start(status: .unlocked)
        trial.stop(keepingPendingOffer: true)
        #expect(trial.pendingOffer == nil)
    }

    @Test func reconnectGraceIsTenSeconds() {
        #expect(AudienceOutputTrial.reconnectGrace == .seconds(10))
    }
}
