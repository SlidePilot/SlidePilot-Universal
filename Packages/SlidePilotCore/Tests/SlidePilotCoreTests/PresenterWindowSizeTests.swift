import CoreGraphics
import SlidePilotCore
import Testing

@Suite
struct PresenterWindowSizeTests {
    // DOC-04: a new presenter window opens at 1400 × 900 when the screen has room.
    @Test func usesThePreferredSizeOnALargeScreen() {
        let size = PresenterWindowSize.size(forVisibleScreen: CGSize(width: 2560, height: 1410))
        #expect(size == CGSize(width: 1400, height: 900))
    }

    // DOC-04: on a smaller screen it takes the visible area, per dimension.
    @Test func fitsASmallerScreen() {
        #expect(PresenterWindowSize.size(forVisibleScreen: CGSize(width: 1280, height: 775))
            == CGSize(width: 1280, height: 775))
        #expect(PresenterWindowSize.size(forVisibleScreen: CGSize(width: 1512, height: 863.5))
            == CGSize(width: 1400, height: 863))
    }

    @Test func unknownScreenGivesThePreferredSize() {
        #expect(PresenterWindowSize.size(forVisibleScreen: .zero) == PresenterWindowSize.preferred)
    }
}
