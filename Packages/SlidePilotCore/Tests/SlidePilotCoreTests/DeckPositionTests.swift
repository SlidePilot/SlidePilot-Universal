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

    // NAV-03: Go Back returns to the previously viewed page.

    @Test func noPreviousPageBeforeTheFirstChange() {
        var position = DeckPosition(page: 3, pageCount: 6)
        #expect(position.previousPage == nil)
        #expect(!position.canGoBack)
        position.goBack()
        #expect(position.page == 3)
    }

    @Test func goBackAfterAJump() {
        var position = DeckPosition(page: 1, pageCount: 10)
        position.show(7)
        #expect(position.previousPage == 1)
        position.goBack()
        #expect(position.page == 1)
    }

    @Test func goBackTwiceReturnsToTheJumpTarget() {
        var position = DeckPosition(page: 1, pageCount: 10)
        position.show(7)
        position.goBack()
        #expect(position.previousPage == 7)
        position.goBack()
        #expect(position.page == 7)
        #expect(position.previousPage == 1)
    }

    @Test func stepsCountAsPageChanges() {
        var position = DeckPosition(page: 0, pageCount: 10)
        position.show(5)
        position.showNext()
        #expect(position.previousPage == 5)
        position.showPrevious()
        #expect(position.previousPage == 6)
        position.goBack()
        #expect(position.page == 6)
    }

    @Test func stayingOnThePageKeepsThePreviousPage() {
        var position = DeckPosition(page: 2, pageCount: 5)
        position.show(4)
        position.showNext()
        position.show(4)
        position.show(99)
        #expect(position.page == 4)
        #expect(position.previousPage == 2)
    }

    @Test func reloadKeepsThePreviousPage() {
        var position = DeckPosition(page: 2, pageCount: 6)
        position.show(4)
        position.changePageCount(to: 8)
        #expect(position.previousPage == 2)
        position.goBack()
        #expect(position.page == 2)
    }

    @Test func reloadDropsAPreviousPageThatNoLongerExists() {
        var position = DeckPosition(page: 7, pageCount: 9)
        position.show(1)
        position.changePageCount(to: 5)
        #expect(position.previousPage == nil)
        #expect(position.page == 1)
    }

    @Test func reloadDropsAPreviousPageThatBecameCurrent() {
        var position = DeckPosition(page: 3, pageCount: 9)
        position.show(8)
        position.changePageCount(to: 4)
        #expect(position.page == 3)
        #expect(position.previousPage == nil)
    }
}
