import Foundation
import SlidePilotCore
import Testing

@MainActor
@Suite
struct DonationHintTests {
    // DROP-03: the hint is due from the fifth launch on, not earlier.
    @Test func isDueFromTheFifthLaunch() {
        let hint = DonationHint(store: InMemorySettingsStore())
        for _ in 1...4 {
            hint.recordLaunch()
            #expect(!hint.presentIfDue())
        }
        hint.recordLaunch()
        #expect(hint.launchCount == 5)
        #expect(hint.presentIfDue())
    }

    // Shown once only, also when several windows ask in the same launch or later launches.
    @Test func isPresentedOnce() {
        let store = InMemorySettingsStore(values: [DonationHint.Key.launchCount: 5])
        let hint = DonationHint(store: store)
        #expect(hint.presentIfDue())
        #expect(!hint.presentIfDue())
        #expect(store.values[DonationHint.Key.alreadyShown] as? Bool == true)

        let nextLaunch = DonationHint(store: store)
        nextLaunch.recordLaunch()
        #expect(!nextLaunch.presentIfDue())
    }

    // Like the old app, counting stops at six.
    @Test func countingStopsAtSix() {
        let store = InMemorySettingsStore()
        let hint = DonationHint(store: store)
        for _ in 1...10 { hint.recordLaunch() }
        #expect(hint.launchCount == 6)
        #expect(store.values[DonationHint.Key.launchCount] as? Int == 6)
    }

    // A user who reached the limit without seeing the hint still gets it.
    @Test func isDueAtTheLimit() {
        let hint = DonationHint(store: InMemorySettingsStore(values: [DonationHint.Key.launchCount: 6]))
        hint.recordLaunch()
        #expect(hint.presentIfDue())
    }

    @Test func usesTheOldKeysAndPage() {
        #expect(DonationHint.Key.launchCount == "AppStartCount")
        #expect(DonationHint.Key.alreadyShown == "AlreadyDisplayedDonationAlert")
        #expect(DonationHint.donationURL.absoluteString == "https://slidepilotapp.com/donate.html")
    }
}
