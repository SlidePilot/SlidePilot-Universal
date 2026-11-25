import CoreGraphics
import SlidePilotCore
import Testing

@Suite
struct PresenterWindowSizeTests {
    // DOC-04: a new presenter window takes 85 % of the visible screen.
    @Test func takesEightyFivePercentOfTheVisibleScreen() {
        let size = PresenterWindowSize.size(forVisibleScreen: CGSize(width: 1512, height: 944))
        #expect(size == CGSize(width: 1285, height: 802))
    }

    @Test func emptyScreenGivesEmptySize() {
        #expect(PresenterWindowSize.size(forVisibleScreen: .zero) == .zero)
    }
}
