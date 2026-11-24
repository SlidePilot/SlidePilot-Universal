import SlidePilotCore
import Testing

@Suite
struct PresenterSlotTitleTests {
    @Test func currentSlotCountsFromOne() {
        let position = DeckPosition(page: 6, pageCount: 18)
        #expect(PresenterSlotTitle(slot: .current, position: position) == .current(SlideCounter(number: 7, count: 18)))
    }

    @Test func nextSlotBeforeTheLastSlide() {
        let position = DeckPosition(page: 16, pageCount: 18)
        #expect(PresenterSlotTitle(slot: .next, position: position) == .next)
    }

    @Test func nextSlotAfterTheLastSlide() {
        let position = DeckPosition(page: 17, pageCount: 18)
        #expect(PresenterSlotTitle(slot: .next, position: position) == .endOfPresentation)
    }

    @Test func singlePageDeckHasNoNextSlide() {
        #expect(PresenterSlotTitle(slot: .next, position: DeckPosition(pageCount: 1)) == .endOfPresentation)
    }

    @Test func notesSlotHasNoCounter() {
        #expect(PresenterSlotTitle(slot: .notes, position: DeckPosition(page: 3, pageCount: 18)) == .notes)
    }

    @Test func counterFollowsAShorterReload() {
        var position = DeckPosition(page: 9, pageCount: 10)
        position.changePageCount(to: 5)
        #expect(SlideCounter(position) == SlideCounter(number: 5, count: 5))
        #expect(PresenterSlotTitle(slot: .next, position: position) == .endOfPresentation)
    }
}
