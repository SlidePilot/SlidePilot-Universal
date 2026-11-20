import Foundation
import Testing
@testable import SlidePilotRemoteProtocol

@Suite("Remote controller state (REM-04, REM-05, REM-07)")
struct ControllerStateTests {
    let deckA = PresentationSummary(id: PresentationID(), title: "Talk A", slideCount: 5)
    let deckB = PresentationSummary(id: PresentationID(), title: "Talk B", slideCount: 3)
    let size = PixelSize(width: 800, height: 600)

    func status(_ deck: PresentationSummary, slide: Int = 0, curtain: RemoteCurtain = .none) -> PresentationStatus {
        PresentationStatus(presentationID: deck.id, slideIndex: slide, slideCount: deck.slideCount, curtain: curtain, notesRTF: nil)
    }

    func images(_ deck: PresentationSummary, slide: Int = 0) -> SlideImages {
        let image = EncodedImage(format: .jpeg, pixelWidth: 1, pixelHeight: 1, data: Data([1]))
        return SlideImages(presentationID: deck.id, slideIndex: slide, current: image, next: nil, notes: nil)
    }

    /// Connected, two decks listed, deck A selected.
    func selectedState() -> RemoteControllerState {
        var state = RemoteControllerState()
        state.connectionVerified()
        _ = state.receive(.presentations([deckA, deckB]))
        _ = state.select(deckA.id)
        return state
    }

    @Test func selectingSendsTheImageSize() {
        var state = RemoteControllerState()
        state.connectionVerified()
        #expect(state.setImageSize(size).isEmpty)
        #expect(state.receive(.presentations([deckA, deckB])).isEmpty)
        #expect(state.select(deckB.id) == [.selectPresentation(deckB.id, imageSize: size)])
        #expect(state.selectedPresentation == deckB)
    }

    @Test func theOnlyPresentationIsSelectedRightAway() {
        var state = RemoteControllerState()
        state.connectionVerified()
        let messages = state.receive(.presentations([deckA]))
        #expect(messages == [.selectPresentation(deckA.id, imageSize: PixelSize(width: 1, height: 1))])
        #expect(state.selection == deckA.id)
    }

    @Test func aLaterListDoesNotSelectByItself() {
        var state = RemoteControllerState()
        state.connectionVerified()
        _ = state.receive(.presentations([]))
        #expect(state.receive(.presentations([deckA])).isEmpty)
        #expect(state.selection == nil)
    }

    @Test func unknownSelectionIsIgnored() {
        var state = RemoteControllerState()
        _ = state.receive(.presentations([deckA, deckB]))
        #expect(state.select(PresentationID()).isEmpty)
        #expect(state.selection == nil)
    }

    @Test func statusAndImagesOfOtherPresentationsAreIgnored() {
        var state = selectedState()
        _ = state.receive(.status(status(deckB, slide: 2)))
        _ = state.receive(.slideImages(images(deckB)))
        #expect(state.status == nil)
        #expect(state.images == nil)
        _ = state.receive(.status(status(deckA, slide: 2)))
        _ = state.receive(.slideImages(images(deckA, slide: 2)))
        #expect(state.status?.slideNumber == 3)
        #expect(state.images?.slideIndex == 2)
    }

    @Test func imageSizeChangesAreSentOnlyWithASelection() {
        var state = selectedState()
        #expect(state.setImageSize(size) == [.setImageSize(size)])
        #expect(state.setImageSize(size).isEmpty)
        _ = state.deselect()
        #expect(state.setImageSize(PixelSize(width: 10, height: 10)).isEmpty)
    }

    @Test func requestedImageSizeIsRoundedUp() {
        #expect(RemoteControllerState.requestedImageSize(width: 800, height: 601) == PixelSize(width: 896, height: 640))
        #expect(RemoteControllerState.requestedImageSize(width: 0, height: .nan) == PixelSize(width: 128, height: 128))
        #expect(RemoteControllerState.requestedImageSize(width: 100_000, height: 256) == PixelSize(width: 8192, height: 256))
    }

    @Test func commandsNeedASelection() {
        var state = RemoteControllerState()
        #expect(state.command(.nextSlide).isEmpty)
        state = selectedState()
        #expect(state.command(.nextSlide) == [.nextSlide])
        #expect(state.command(.previousSlide) == [.previousSlide])
        #expect(state.command(.setCurtain(.white)) == [.setCurtain(.white)])
        #expect(state.command(.pointerMoved(PointerPosition(x: 0.5, y: 0.25))) == [.pointerMoved(PointerPosition(x: 0.5, y: 0.25))])
        #expect(state.command(.pointerFinished) == [.pointerFinished])
    }

    @Test func deselectingFinishesThePointer() {
        var state = selectedState()
        #expect(state.deselect() == [.pointerFinished])
        #expect(state.selection == nil)
        #expect(state.deselect().isEmpty)
    }

    @Test func closedPresentationIsReported() {
        var state = selectedState()
        _ = state.receive(.status(status(deckA)))
        _ = state.receive(.presentationClosed(deckB.id))
        #expect(state.selection == deckA.id)
        _ = state.receive(.presentationClosed(deckA.id))
        #expect(state.selection == nil)
        #expect(state.status == nil)
        #expect(state.closedTitle == "Talk A")
        // Picking another presentation clears the message.
        _ = state.select(deckB.id)
        #expect(state.closedTitle == nil)
    }

    @Test func presentationMissingFromTheListIsClosed() {
        var state = selectedState()
        _ = state.receive(.presentations([deckB]))
        #expect(state.selection == nil)
        #expect(state.closedTitle == "Talk A")
    }

    @Test func reconnectSelectsThePreviousPresentationAgain() {
        var state = selectedState()
        _ = state.setImageSize(size)
        _ = state.receive(.status(status(deckA, slide: 3)))
        state.connectionVerified()
        #expect(state.status == nil)
        #expect(state.presentations.isEmpty)
        #expect(!state.hasPresentations)
        #expect(state.receive(.presentations([deckB, deckA])) == [.selectPresentation(deckA.id, imageSize: size)])
    }

    @Test func reconnectWithoutThePreviousPresentation() {
        var state = selectedState()
        state.connectionVerified()
        #expect(state.receive(.presentations([deckB])) == [.selectPresentation(deckB.id, imageSize: PixelSize(width: 1, height: 1))])
        var other = selectedState()
        other.connectionVerified()
        let third = PresentationSummary(id: PresentationID(), title: "C", slideCount: 1)
        #expect(other.receive(.presentations([deckB, third])).isEmpty)
    }

    @Test func curtainButtonTogglesBlack() {
        var state = selectedState()
        #expect(state.curtainToggleTarget == .black)
        _ = state.receive(.status(status(deckA, curtain: .black)))
        #expect(state.curtainToggleTarget == .none)
        _ = state.receive(.status(status(deckA, curtain: .white)))
        #expect(state.curtainToggleTarget == .none)
    }

    @Test func progressCountsTheCurrentSlide() {
        var state = selectedState()
        #expect(state.progress == nil)
        _ = state.receive(.status(status(deckA, slide: 0)))
        #expect(state.progress == 0.2)
        _ = state.receive(.status(status(deckA, slide: 4)))
        #expect(state.progress == 1)
    }
}

@Suite("Remote controller gestures (REM-07)")
struct GestureInterpreterTests {
    typealias Point = RemoteGestureInterpreter.Point
    let origin = Point(x: 100, y: 100)
    let middle = PointerPosition(x: 0.5, y: 0.5)

    func tap(_ interpreter: inout RemoteGestureInterpreter, at point: Point, time: Double) {
        _ = interpreter.moved(start: point, location: point, time: time, slidePosition: middle)
        _ = interpreter.ended(start: point, location: point, time: time + 0.1)
    }

    @Test func swipeLeftShowsTheNextSlide() {
        var interpreter = RemoteGestureInterpreter()
        _ = interpreter.moved(start: origin, location: Point(x: 60, y: 105), time: 0, slidePosition: middle)
        #expect(interpreter.ended(start: origin, location: Point(x: 30, y: 110), time: 0.2) == [.nextSlide])
    }

    @Test func swipeRightShowsThePreviousSlide() {
        var interpreter = RemoteGestureInterpreter()
        _ = interpreter.moved(start: origin, location: origin, time: 0, slidePosition: middle)
        #expect(interpreter.ended(start: origin, location: Point(x: 200, y: 90), time: 0.2) == [.previousSlide])
    }

    @Test func shortOrVerticalMovesDoNothing() {
        var interpreter = RemoteGestureInterpreter()
        _ = interpreter.moved(start: origin, location: origin, time: 0, slidePosition: middle)
        #expect(interpreter.ended(start: origin, location: Point(x: 130, y: 100), time: 0.2).isEmpty)
        _ = interpreter.moved(start: origin, location: origin, time: 1, slidePosition: middle)
        #expect(interpreter.ended(start: origin, location: Point(x: 160, y: 200), time: 1.2).isEmpty)
    }

    @Test func doubleTapAndDragMovesThePointer() {
        var interpreter = RemoteGestureInterpreter()
        tap(&interpreter, at: origin, time: 0)
        let second = Point(x: 105, y: 98)
        #expect(interpreter.moved(start: second, location: second, time: 0.3, slidePosition: middle) == [.pointerMoved(middle)])
        #expect(interpreter.isMovingPointer)
        let edge = PointerPosition(x: 1, y: 0)
        // A long drag moves the pointer and is no swipe.
        #expect(interpreter.moved(start: second, location: Point(x: 400, y: 98), time: 0.5, slidePosition: edge) == [.pointerMoved(edge)])
        #expect(interpreter.ended(start: second, location: Point(x: 400, y: 98), time: 0.6) == [.pointerFinished])
        #expect(!interpreter.isMovingPointer)
    }

    @Test func slowSecondTapDoesNotMoveThePointer() {
        var interpreter = RemoteGestureInterpreter()
        tap(&interpreter, at: origin, time: 0)
        #expect(interpreter.moved(start: origin, location: origin, time: 1, slidePosition: middle).isEmpty)
    }

    @Test func distantSecondTapDoesNotMoveThePointer() {
        var interpreter = RemoteGestureInterpreter()
        tap(&interpreter, at: origin, time: 0)
        let far = Point(x: 300, y: 100)
        #expect(interpreter.moved(start: far, location: far, time: 0.2, slidePosition: middle).isEmpty)
    }

    @Test func aLongPressIsNoTap() {
        var interpreter = RemoteGestureInterpreter()
        _ = interpreter.moved(start: origin, location: origin, time: 0, slidePosition: middle)
        _ = interpreter.ended(start: origin, location: origin, time: 1)
        #expect(interpreter.moved(start: origin, location: origin, time: 1.1, slidePosition: middle).isEmpty)
    }

    @Test func tripleTapStartsThePointerOnlyOnce() {
        var interpreter = RemoteGestureInterpreter()
        tap(&interpreter, at: origin, time: 0)
        // The second tap moves the pointer briefly, and the third starts fresh.
        tap(&interpreter, at: origin, time: 0.2)
        #expect(interpreter.moved(start: origin, location: origin, time: 0.4, slidePosition: middle).isEmpty)
    }

    @Test func pinchCancelsSwipeAndPointer() {
        var interpreter = RemoteGestureInterpreter()
        _ = interpreter.moved(start: origin, location: origin, time: 0, slidePosition: middle)
        #expect(interpreter.cancel().isEmpty)
        #expect(interpreter.ended(start: origin, location: Point(x: 0, y: 100), time: 0.2).isEmpty)

        tap(&interpreter, at: origin, time: 1)
        _ = interpreter.moved(start: origin, location: origin, time: 1.2, slidePosition: middle)
        #expect(interpreter.cancel() == [.pointerFinished])
        #expect(interpreter.moved(start: origin, location: Point(x: 10, y: 10), time: 1.3, slidePosition: middle).isEmpty)
        #expect(interpreter.ended(start: origin, location: origin, time: 1.4).isEmpty)
    }
}
