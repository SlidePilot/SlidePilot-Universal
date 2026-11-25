import SlidePilotCore
import Testing

@Suite
struct ProStatusTests {
    // PRO-01: without Pro, audience output and remote control are a trial.
    @Test(arguments: LimitedFeature.allCases)
    func lockedLimitsEveryLimitedFeature(_ feature: LimitedFeature) {
        #expect(ProStatus.locked.limits(feature))
    }

    // PRO-01: an unknown status limits, so nothing runs unlimited before the check.
    @Test(arguments: LimitedFeature.allCases)
    func unknownLimitsLikeLocked(_ feature: LimitedFeature) {
        #expect(ProStatus.unknown.limits(feature))
        #expect(!ProStatus.unknown.unlocksEverything)
    }

    @Test(arguments: LimitedFeature.allCases)
    func unlockedLimitsNothing(_ feature: LimitedFeature) {
        #expect(!ProStatus.unlocked.limits(feature))
        #expect(ProStatus.unlocked.unlocksEverything)
    }

    // ADR 0020: the free Mac download has no limit at all.
    @Test(arguments: LimitedFeature.allCases)
    func freeDownloadLimitsNothing(_ feature: LimitedFeature) {
        #expect(!ProStatus.unlimited.limits(feature))
        #expect(ProStatus.unlimited.unlocksEverything)
    }

    // ADR 0020: exactly audience output and remote control (both directions) are limited.
    @Test func limitedFeaturesAreOutputAndRemote() {
        #expect(Set(LimitedFeature.allCases) == [.audienceOutput, .remoteControl])
    }

    // PRO-05: the hint shows only once the status is known to be locked.
    @Test func trialHintOnlyWhenLocked() {
        #expect(ProStatus.locked.showsTrialHint)
        #expect(!ProStatus.unknown.showsTrialHint)
        #expect(!ProStatus.unlocked.showsTrialHint)
        #expect(!ProStatus.unlimited.showsTrialHint)
    }
}
