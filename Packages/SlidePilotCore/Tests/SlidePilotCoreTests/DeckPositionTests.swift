import SlidePilotCore
import Testing

@Suite
struct DeckPositionTests {
    @Test func clampsInitialPage() {
        #expect(DeckPosition(page: 9, pageCount: 5).page == 4)
        #expect(DeckPosition(page: -1, pageCount: 5).page == 0)
    }

    @Test func stopsAtFirstAndLastPage() {
        var position = DeckPosition(page: 4, pageCount: 5)
        position.showNext()
        #expect(position.page == 4)
        position.show(0)
        position.showPrevious()
        #expect(position.page == 0)
    }

    // DEF-18: the old app kept an index past the end of a shorter deck.
    @Test func shorterDeckClampsToLastPage() {
        var position = DeckPosition(page: 5, pageCount: 6)
        position.changePageCount(to: 4)
        #expect(position.page == 3)
        #expect(position.pageCount == 4)
    }

    @Test func reloadKeepsPage() {
        var position = DeckPosition(page: 2, pageCount: 6)
        position.changePageCount(to: 6)
        #expect(position.page == 2)
        position.changePageCount(to: 9)
        #expect(position.page == 2)
        position.showNext()
        #expect(position.page == 3)
    }

    @Test func emptyDeckStaysOnFirstPage() {
        var position = DeckPosition(page: 3, pageCount: 0)
        #expect(position.page == 0)
        position.showNext()
        #expect(position.page == 0)
    }
}
