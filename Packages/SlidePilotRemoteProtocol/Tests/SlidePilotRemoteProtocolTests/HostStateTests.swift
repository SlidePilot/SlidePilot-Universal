import Foundation
import Testing
import SlidePilotCore
@testable import SlidePilotRemoteProtocol

@Suite("Remote host state (REM-04, REM-05, REM-06)")
struct HostStateTests {
    typealias State = RemoteHostState<Int>

    let deckA = PresentationID()
    let deckB = PresentationID()
    let size = PixelSize(width: 800, height: 600)

    func presentation(
        _ id: PresentationID,
        title: String = "Talk",
        slide: Int = 0,
        count: Int = 5,
        curtain: RemoteCurtain = .none,
        notes: Data? = nil,
        version: Int = 0
    ) -> HostedPresentation {
        HostedPresentation(id: id, title: title, slideIndex: slide, slideCount: count, curtain: curtain, notesRTF: notes, contentVersion: version)
    }

    func status(_ id: PresentationID, slide: Int = 0, count: Int = 5, curtain: RemoteCurtain = .none, notes: Data? = nil) -> HostMessage {
        .status(PresentationStatus(presentationID: id, slideIndex: slide, slideCount: count, curtain: curtain, notesRTF: notes))
    }

    func images(_ id: PresentationID, slide: Int = 0, next: Int? = 1, size: PixelSize? = nil, version: Int = 0) -> SlideImageRequest {
        SlideImageRequest(presentationID: id, slideIndex: slide, nextSlideIndex: next, size: size ?? self.size, contentVersion: version)
    }

    /// A state with deck A open and controller 1 verified and on deck A.
    func selectedState() -> State {
        var state = State()
        _ = state.update([presentation(deckA)])
        _ = state.controllerVerified(1)
        _ = state.receive(.selectPresentation(deckA, imageSize: size), from: 1)
        return state
    }

    // MARK: - Verification (REM-06)

    @Test func unverifiedControllersGetNothingAndCannotCommand() {
        var state = State()
        _ = state.update([presentation(deckA)])
        #expect(state.receive(.selectPresentation(deckA, imageSize: size), from: 1).isEmpty)
        #expect(state.receive(.nextSlide, from: 1).isEmpty)
        #expect(state.receive(.setCurtain(.black), from: 1).isEmpty)
        #expect(state.update([presentation(deckA, slide: 1)]).isEmpty)
    }

    @Test func controllerThatLeftGetsNothingAndCannotCommand() {
        var state = selectedState()
        #expect(state.controllerLeft(1) == [.perform(.pointerFinished, on: deckA)])
        #expect(!state.isVerified(1))
        #expect(state.receive(.nextSlide, from: 1).isEmpty)
        #expect(state.update([presentation(deckA, slide: 2)]).isEmpty)
    }

    // MARK: - Content (REM-04)

    @Test func verifiedControllerGetsTheListOfOpenPresentations() {
        var state = State()
        _ = state.update([presentation(deckA, title: "A", count: 3), presentation(deckB, title: "B", count: 9)])
        #expect(state.controllerVerified(1) == [
            .send(.presentations([
                PresentationSummary(id: deckA, title: "A", slideCount: 3),
                PresentationSummary(id: deckB, title: "B", slideCount: 9),
            ]), to: 1),
        ])
    }

    @Test func selectionSendsStatusThenImages() {
        var state = State()
        _ = state.update([presentation(deckA, slide: 2, curtain: .white, notes: Data("rtf".utf8))])
        _ = state.controllerVerified(1)
        #expect(state.receive(.selectPresentation(deckA, imageSize: size), from: 1) == [
            .send(status(deckA, slide: 2, curtain: .white, notes: Data("rtf".utf8)), to: 1),
            .sendImages(images(deckA, slide: 2, next: 3), to: 1),
        ])
        #expect(state.selection(of: 1) == deckA)
    }

    @Test func selectingAClosedPresentationAnswersClosed() {
        var state = State()
        _ = state.update([presentation(deckA)])
        _ = state.controllerVerified(1)
        #expect(state.receive(.selectPresentation(deckB, imageSize: size), from: 1) == [.send(.presentationClosed(deckB), to: 1)])
        #expect(state.selection(of: 1) == nil)
    }

    @Test func pageChangeSendsStatusAndImages() {
        var state = selectedState()
        #expect(state.update([presentation(deckA, slide: 1)]) == [
            .send(status(deckA, slide: 1), to: 1),
            .sendImages(images(deckA, slide: 1, next: 2), to: 1),
        ])
    }

    @Test func lastSlideHasNoNextImage() {
        var state = selectedState()
        let actions = state.update([presentation(deckA, slide: 4)])
        #expect(actions.last == .sendImages(images(deckA, slide: 4, next: nil), to: 1))
    }

    @Test func curtainChangeSendsOnlyStatus() {
        var state = selectedState()
        #expect(state.update([presentation(deckA, curtain: .black)]) == [.send(status(deckA, curtain: .black), to: 1)])
    }

    @Test func notesEditSendsOnlyStatus() {
        var state = selectedState()
        let notes = Data("{\\rtf1 Hello}".utf8)
        #expect(state.update([presentation(deckA, notes: notes)]) == [.send(status(deckA, notes: notes), to: 1)])
    }

    @Test func reloadAndNotesPositionChangeSendImages() {
        var state = selectedState()
        #expect(state.update([presentation(deckA, version: 1)]) == [.sendImages(images(deckA, version: 1), to: 1)])
    }

    @Test func reloadWithNewSlideCountSendsListStatusAndImages() {
        var state = selectedState()
        #expect(state.update([presentation(deckA, count: 2, version: 1)]) == [
            .send(.presentations([PresentationSummary(id: deckA, title: "Talk", slideCount: 2)]), to: 1),
            .send(status(deckA, count: 2), to: 1),
            .sendImages(images(deckA, version: 1), to: 1),
        ])
    }

    /// A renamed PDF keeps its presentation and only gets a new name in the list (#237).
    @Test func renamedPresentationSendsOnlyTheList() {
        var state = selectedState()
        #expect(state.update([presentation(deckA, title: "Renamed")]) == [
            .send(.presentations([PresentationSummary(id: deckA, title: "Renamed", slideCount: 5)]), to: 1),
        ])
        #expect(state.selection(of: 1) == deckA)
    }

    @Test func unchangedPresentationsSendNothing() {
        var state = selectedState()
        #expect(state.update([presentation(deckA)]).isEmpty)
    }

    @Test func newImageSizeResendsImagesOnlyWhenItChanged() {
        var state = selectedState()
        #expect(state.receive(.setImageSize(size), from: 1).isEmpty)
        let bigger = PixelSize(width: 1600, height: 1200)
        #expect(state.receive(.setImageSize(bigger), from: 1) == [.sendImages(images(deckA, size: bigger), to: 1)])
    }

    @Test func hugeImageSizesAreLimited() {
        var state = selectedState()
        let actions = state.receive(.setImageSize(PixelSize(width: 100_000, height: 50_000)), from: 1)
        #expect(actions == [.sendImages(images(deckA, size: PixelSize(width: 4096, height: 2048)), to: 1)])
    }

    @Test func openingAnotherDocumentSendsTheListToAllControllers() {
        var state = selectedState()
        _ = state.controllerVerified(2)
        let actions = state.update([presentation(deckA), presentation(deckB, title: "B")])
        let list = HostMessage.presentations([
            PresentationSummary(id: deckA, title: "Talk", slideCount: 5),
            PresentationSummary(id: deckB, title: "B", slideCount: 5),
        ])
        #expect(actions == [.send(list, to: 1), .send(list, to: 2)])
    }

    @Test func closingTheSelectedPresentationTellsTheController() {
        var state = selectedState()
        #expect(state.update([presentation(deckB)]) == [
            .send(.presentations([PresentationSummary(id: deckB, title: "Talk", slideCount: 5)]), to: 1),
            .send(.presentationClosed(deckA), to: 1),
        ])
        #expect(state.selection(of: 1) == nil)
        #expect(state.receive(.nextSlide, from: 1).isEmpty)
    }

    @Test func controllersOnlyGetUpdatesOfTheirSelection() {
        var state = selectedState()
        _ = state.update([presentation(deckA), presentation(deckB)])
        _ = state.controllerVerified(2)
        _ = state.receive(.selectPresentation(deckB, imageSize: size), from: 2)
        #expect(state.update([presentation(deckA), presentation(deckB, slide: 1)]) == [
            .send(status(deckB, slide: 1), to: 2),
            .sendImages(images(deckB, slide: 1, next: 2), to: 2),
        ])
    }

    @Test func selectingAgainResendsEverything() {
        var state = selectedState()
        #expect(state.receive(.selectPresentation(deckA, imageSize: size), from: 1).count == 2)
    }

    // MARK: - Commands (REM-05)

    @Test func commandsApplyToTheSelectedPresentation() {
        var state = selectedState()
        let position = PointerPosition(x: 0.25, y: 0.75)
        #expect(state.receive(.nextSlide, from: 1) == [.perform(.nextSlide, on: deckA)])
        #expect(state.receive(.previousSlide, from: 1) == [.perform(.previousSlide, on: deckA)])
        #expect(state.receive(.setCurtain(.black), from: 1) == [.perform(.setCurtain(.black), on: deckA)])
        #expect(state.receive(.setCurtain(.white), from: 1) == [.perform(.setCurtain(.white), on: deckA)])
        #expect(state.receive(.setCurtain(.none), from: 1) == [.perform(.setCurtain(.none), on: deckA)])
        #expect(state.receive(.pointerMoved(position), from: 1) == [.perform(.pointerMoved(position), on: deckA)])
        #expect(state.receive(.pointerFinished, from: 1) == [.perform(.pointerFinished, on: deckA)])
    }

    @Test func controllerWithoutSelectionLeavesNoPointerBehind() {
        var state = State()
        _ = state.controllerVerified(1)
        #expect(state.controllerLeft(1).isEmpty)
    }

    @Test func selectingAnotherPresentationHidesThePointerOnThePreviousOne() {
        var state = selectedState()
        _ = state.update([presentation(deckA), presentation(deckB)])
        let actions = state.receive(.selectPresentation(deckB, imageSize: size), from: 1)
        #expect(actions.first == .perform(.pointerFinished, on: deckA))
        #expect(actions.count == 3)
    }

    @Test func commandsWithoutSelectionAreIgnored() {
        var state = State()
        _ = state.update([presentation(deckA)])
        _ = state.controllerVerified(1)
        #expect(state.receive(.nextSlide, from: 1).isEmpty)
        #expect(state.receive(.pointerFinished, from: 1).isEmpty)
    }
}

@Suite("Remote curtain mapping (REM-04, REM-05)")
struct RemoteCurtainTests {
    @Test(arguments: [(Curtain.none, RemoteCurtain.none), (.black, .black), (.white, .white)])
    func mapsBothWays(curtain: Curtain, remote: RemoteCurtain) {
        #expect(RemoteCurtain(curtain) == remote)
        #expect(Curtain(remote) == curtain)
    }
}
