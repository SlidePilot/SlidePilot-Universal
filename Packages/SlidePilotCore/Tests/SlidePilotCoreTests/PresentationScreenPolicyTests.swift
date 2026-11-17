import CoreGraphics
import SlidePilotCore
import Testing

@Suite
struct PresentationScreenPolicyTests {
    typealias Policy = PresentationScreenPolicy

    @Test func startsWhenOpeningOnlyWithSecondScreen() {
        #expect(!Policy.startsWhenOpening(screenCount: 1))
        #expect(Policy.startsWhenOpening(screenCount: 2))
        #expect(Policy.startsWhenOpening(screenCount: 3))
    }

    @Test func singleScreenIsShared() {
        #expect(Policy.screen(in: [1], presenterScreen: 1) == 1)
        #expect(Policy.screen(in: [Int](), presenterScreen: nil) == nil)
    }

    // Old app: NSScreen.screens[1].
    @Test func secondScreenLikeOldApp() {
        #expect(Policy.screen(in: [1, 2], presenterScreen: 1) == 2)
        #expect(Policy.screen(in: [1, 2, 3], presenterScreen: nil) == 2)
    }

    @Test func avoidsPresenterScreen() {
        #expect(Policy.screen(in: [1, 2], presenterScreen: 2) == 1)
        #expect(Policy.screen(in: [1, 2, 3], presenterScreen: 2) == 1)
    }

    // Test M3 of the findings: a screen plugged in while presenting on the built-in screen.
    @Test func addedScreenTakesOverSharedPresentation() {
        let reaction = Policy.reaction(previous: [1], current: [1, 2], presentationScreen: 1, presenterScreen: 1)
        #expect(reaction == .reopen(on: 2))
    }

    @Test func presentationOnOwnScreenStays() {
        let reaction = Policy.reaction(previous: [1, 2], current: [1, 2, 3], presentationScreen: 2, presenterScreen: 1)
        #expect(reaction == .keep)
    }

    @Test func removedScreenReopensOnRemainingScreen() {
        #expect(Policy.reaction(previous: [1, 2], current: [1], presentationScreen: 2, presenterScreen: 1) == .reopen(on: 1))
        #expect(Policy.reaction(previous: [1, 2, 3], current: [1, 3], presentationScreen: 2, presenterScreen: 1) == .reopen(on: 3))
    }

    @Test func removingAnotherScreenKeepsPresentation() {
        let reaction = Policy.reaction(previous: [1, 2, 3], current: [1, 2], presentationScreen: 2, presenterScreen: 1)
        #expect(reaction == .keep)
    }

    @Test func unchangedScreensKeepPresentation() {
        #expect(Policy.reaction(previous: [1], current: [1], presentationScreen: 1, presenterScreen: 1) == .keep)
        #expect(Policy.reaction(previous: [1, 2], current: [1, 2], presentationScreen: 2, presenterScreen: 1) == .keep)
    }

    @Test func unknownPresentationScreenKeepsPresentation() {
        #expect(Policy.reaction(previous: [1], current: [1, 2], presentationScreen: nil, presenterScreen: 1) == .keep)
    }

    // Hardware test M3: macOS moved the presenter to the new screen together with the presentation.
    @Test func presenterReturnsWhenMovedOntoPresentationScreen() {
        #expect(Policy.presenterShouldReturn(from: 2, to: 1, presentationScreen: 2, screens: [1, 2]))
    }

    @Test func presenterStaysWhenNotOnPresentationScreen() {
        #expect(!Policy.presenterShouldReturn(from: 3, to: 1, presentationScreen: 2, screens: [1, 2, 3]))
        #expect(!Policy.presenterShouldReturn(from: 1, to: 1, presentationScreen: 2, screens: [1, 2]))
    }

    @Test func presenterStaysWhenPreviousScreenIsGone() {
        #expect(!Policy.presenterShouldReturn(from: 2, to: 1, presentationScreen: 2, screens: [2]))
        #expect(!Policy.presenterShouldReturn(from: nil, to: 1, presentationScreen: 2, screens: [1, 2]))
    }

    @Test func frameFollowsItsScreenWhenTheMainScreenChanges() {
        // The built-in screen was main at (0, 0); an external screen became main to its left.
        let saved = CGRect(x: 100, y: 50, width: 800, height: 600)
        let builtInBefore = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let builtInNow = CGRect(x: 1920, y: -100, width: 1512, height: 982)
        #expect(Policy.frame(saved, savedOn: builtInBefore, screenNowAt: builtInNow)
            == CGRect(x: 2020, y: -50, width: 800, height: 600))
        #expect(Policy.frame(saved, savedOn: builtInBefore, screenNowAt: builtInBefore) == saved)
    }
}
