import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct MovieActivationTests {
    @Test func defaultsPlayTheWholeFileOnceOnRequest() {
        let activation = MovieActivation()
        #expect(activation.mode == .once)
        #expect(!activation.autostarts)
        #expect(!activation.loops)
        #expect(activation.playbackRange(fileDuration: 4) == (0, nil))
        #expect(activation.playbackRange(fileDuration: nil) == (0, nil))
    }

    /// Repeat is Beamer's `loop` and `repeat`; palindrome plays as a loop.
    @Test(arguments: [
        (MovieActivation.Mode.once, false),
        (.open, false),
        (.repeat, true),
        (.palindrome, true),
    ])
    func loopsForRepeatAndPalindrome(mode: MovieActivation.Mode, loops: Bool) {
        #expect(MovieActivation(mode: mode).loops == loops)
    }

    @Test func playsThePartGivenByStartAndDuration() {
        let activation = MovieActivation(start: 1, duration: 2)
        #expect(activation.playbackRange(fileDuration: 4) == (1, 3))
        #expect(activation.playbackRange(fileDuration: nil) == (1, 3))
        #expect(MovieActivation(start: 1).playbackRange(fileDuration: 4) == (1, nil))
        #expect(MovieActivation(duration: 2).playbackRange(fileDuration: 4) == (0, 2))
    }

    @Test func clampsTheRangeToTheFile() {
        // A duration past the end stops at the end.
        #expect(MovieActivation(start: 3, duration: 5).playbackRange(fileDuration: 4) == (3, 4))
        // A start at or past the end plays the whole file instead of nothing.
        #expect(MovieActivation(start: 4, duration: 1).playbackRange(fileDuration: 4) == (0, 1))
        #expect(MovieActivation(start: 9).playbackRange(fileDuration: 4) == (0, nil))
    }

    @Test func ignoresInvalidTimes() {
        #expect(MovieActivation(start: -1, duration: 0).playbackRange(fileDuration: 4) == (0, nil))
        #expect(MovieActivation(start: .nan, duration: -2).playbackRange(fileDuration: 4) == (0, nil))
        #expect(MovieActivation(start: .infinity, duration: .infinity).playbackRange(fileDuration: .nan) == (0, nil))
    }

    @Test func convertsPDFTimes() {
        #expect(MovieActivation.seconds(640, scale: 128) == 5)
        #expect(MovieActivation.seconds(3) == 3)
        #expect(MovieActivation.seconds(3, scale: 0) == 3)
        #expect(MovieActivation.seconds(.nan) == nil)
    }
}
