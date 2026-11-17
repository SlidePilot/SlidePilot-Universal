import Foundation
import Testing
@testable import SlidePilotRemoteProtocol

struct MessageTests {
    private static let presentation = PresentationID()
    private static let image = EncodedImage(format: .jpeg, pixelWidth: 1600, pixelHeight: 900, data: Data([1, 2, 3]))

    static let hostMessages: [HostMessage] = [
        .presentations([
            PresentationSummary(id: presentation, title: "Talk.pdf", slideCount: 12),
            PresentationSummary(id: PresentationID(), title: "Lecture.pdf", slideCount: 40),
        ]),
        .status(PresentationStatus(presentationID: presentation, slideIndex: 3, slideCount: 12, curtain: .black, notesRTF: Data(#"{\\rtf1 Mention the demo}"#.utf8))),
        .status(PresentationStatus(presentationID: presentation, slideIndex: 0, slideCount: 1, curtain: .none, notesRTF: nil)),
        .slideImages(SlideImages(presentationID: presentation, slideIndex: 11, current: image, next: nil, notes: image)),
        .presentationClosed(presentation),
        .trustRemoved,
    ]

    static let controllerMessages: [ControllerMessage] = [
        .selectPresentation(presentation, imageSize: PixelSize(width: 1170, height: 2532)),
        .setImageSize(PixelSize(width: 800, height: 600)),
        .nextSlide,
        .previousSlide,
        .setCurtain(.white),
        .setCurtain(.none),
        .pointerMoved(PointerPosition(x: 0.25, y: 0.75)),
        .pointerFinished,
    ]

    @Test(arguments: hostMessages)
    func hostMessageRoundTrips(_ message: HostMessage) throws {
        #expect(try HostMessage.fromWire(message.wireData()) == message)
    }

    @Test(arguments: controllerMessages)
    func controllerMessageRoundTrips(_ message: ControllerMessage) throws {
        #expect(try ControllerMessage.fromWire(message.wireData()) == message)
    }

    @Test func unknownTypeIsSkippedNotRejected() throws {
        let future = Data(#"{"type":"laserColor","payload":"red"}"#.utf8)
        #expect(try ControllerMessage.fromWire(future) == nil)
        #expect(try HostMessage.fromWire(future) == nil)
    }

    @Test func malformedMessageIsRejected() {
        #expect(throws: RemoteProtocolError.invalidMessage) {
            try ControllerMessage.fromWire(Data("not json".utf8))
        }
        #expect(throws: RemoteProtocolError.invalidMessage) {
            try ControllerMessage.fromWire(Data(#"{"type":"setCurtain","payload":"purple"}"#.utf8))
        }
    }

    @Test func pointerIsClampedToTheSlide() throws {
        #expect(PointerPosition(x: -0.5, y: 1.5) == PointerPosition(x: 0, y: 1))
        #expect(PointerPosition(x: .nan, y: .infinity) == PointerPosition(x: 0, y: 0))
        let decoded = try ControllerMessage.fromWire(Data(#"{"type":"pointerMoved","payload":{"x":2,"y":-1}}"#.utf8))
        #expect(decoded == .pointerMoved(PointerPosition(x: 1, y: 0)))
    }

    @Test func imageSizeIsAtLeastOnePixel() throws {
        #expect(PixelSize(width: 0, height: -10) == PixelSize(width: 1, height: 1))
        let decoded = try ControllerMessage.fromWire(Data(#"{"type":"setImageSize","payload":{"width":0,"height":0}}"#.utf8))
        #expect(decoded == .setImageSize(PixelSize(width: 1, height: 1)))
    }

    @Test func slideNumberIsOneBased() {
        let status = PresentationStatus(presentationID: PresentationID(), slideIndex: 0, slideCount: 3, curtain: .none, notesRTF: nil)
        #expect(status.slideNumber == 1)
    }
}

struct VersionTests {
    @Test func negotiatesHighestCommonVersion() {
        #expect(ProtocolVersion.negotiate(local: 1...3, peer: 2...5) == 3)
        #expect(ProtocolVersion.negotiate(local: 1...1, peer: 1...1) == 1)
        #expect(ProtocolVersion.negotiate(local: 1...2, peer: 3...4) == nil)
    }

    @Test func mismatchTellsWhichSideIsOutdated() {
        #expect(VersionMismatch(local: 3...4, peer: 1...2).peerNeedsUpdate)
        #expect(!VersionMismatch(local: 1...2, peer: 3...4).peerNeedsUpdate)
    }
}

struct DiscoveryTests {
    @Test func listsOtherInstancesButNeverItself() {
        let me = InstanceID()
        let other = InstanceID()
        #expect(RemoteDiscovery.shouldList(txtRecord: RemoteDiscovery.txtRecord(for: other), localInstanceID: me))
        #expect(!RemoteDiscovery.shouldList(txtRecord: RemoteDiscovery.txtRecord(for: me), localInstanceID: me))
    }

    @Test func ignoresServicesWithoutValidID() {
        #expect(!RemoteDiscovery.shouldList(txtRecord: [:], localInstanceID: InstanceID()))
        #expect(!RemoteDiscovery.shouldList(txtRecord: ["id": "nope"], localInstanceID: InstanceID()))
    }

    @Test func advertisesVersion() {
        #expect(RemoteDiscovery.txtRecord(for: InstanceID())["v"] == String(ProtocolVersion.current))
    }
}
