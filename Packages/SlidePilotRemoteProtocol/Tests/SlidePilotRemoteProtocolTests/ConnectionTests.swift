import Foundation
import Testing
@testable import SlidePilotRemoteProtocol

/// Two in-memory connections wired back to back, standing in for a TCP socket.
private struct Link: ~Copyable {
    var host: HostConnection
    var controller: ControllerConnection
    var hostEvents: [HostConnection.Event] = []
    var controllerEvents: [ControllerConnection.Event] = []

    init(host: consuming HostConnection, controller: consuming ControllerConnection) {
        self.host = host
        self.controller = controller
    }

    mutating func start() throws {
        let toController = try host.start().bytes
        let toHost = try controller.start().bytes
        try pump(toHost: toHost, toController: toController)
    }

    /// Delivers bytes in both directions until neither side has anything left to send.
    mutating func pump(toHost: Data = Data(), toController: Data = Data()) throws {
        var toHost = toHost
        var toController = toController
        while !toHost.isEmpty || !toController.isEmpty {
            if !toHost.isEmpty {
                let output = try host.receive(toHost)
                toHost = Data()
                hostEvents += output.events
                toController += output.bytes
            }
            if !toController.isEmpty {
                let output = try controller.receive(toController)
                toController = Data()
                controllerEvents += output.events
                toHost += output.bytes
            }
        }
    }

    mutating func confirmOnHost() throws {
        let output = try host.confirmPairingCode()
        hostEvents += output.events
        try pump(toController: output.bytes)
    }

    mutating func confirmOnController() throws {
        let output = try controller.confirmPairingCode()
        controllerEvents += output.events
        try pump(toHost: output.bytes)
    }
}

extension RemoteConnection.Event {
    var pairingCode: String? { if case .pairingCode(let code) = self { code } else { nil } }
    var pairedKey: PairingKey? { if case .paired(_, let key) = self { key } else { nil } }
    var message: Incoming? { if case .message(let message) = self { message } else { nil } }
    var isPairingRequired: Bool { if case .pairingRequiredByPeer = self { true } else { false } }
    var isVerified: Bool { if case .verified = self { true } else { false } }
}

private let mac = LocalIdentity(instanceID: InstanceID(), deviceName: "Mac")
private let phone = LocalIdentity(instanceID: InstanceID(), deviceName: "iPhone")

private func untrusted(_: InstanceID) -> PairingKey? { nil }

private func newLink(
    hostKey: PairingKey? = nil,
    controllerKey: PairingKey? = nil
) -> Link {
    Link(
        host: HostConnection(local: mac, trustedKey: { $0 == phone.instanceID ? hostKey : nil }),
        controller: ControllerConnection(local: phone, trustedKey: { $0 == mac.instanceID ? controllerKey : nil })
    )
}

/// Pairs a fresh link and returns both stored keys.
private func pair() throws -> (host: PairingKey, controller: PairingKey) {
    var link = newLink()
    try link.start()
    try link.confirmOnHost()
    try link.confirmOnController()
    return (try #require(link.hostEvents.compactMap(\.pairedKey).first), try #require(link.controllerEvents.compactMap(\.pairedKey).first))
}

/// A handshake frame as a peer would send it, for crafting misbehaving peers.
private func frame(_ message: HandshakeMessage) throws -> Data {
    try FrameEncoder.frame(message.wireData())
}

private func hello(_ identity: LocalIdentity, role: RemoteRole, versions: ClosedRange<Int> = ProtocolVersion.supported) -> HandshakeMessage {
    .hello(Hello(minimumVersion: versions.lowerBound, version: versions.upperBound, instanceID: identity.instanceID, deviceName: identity.deviceName, role: role))
}

struct PairingTests {
    @Test func firstConnectionShowsTheSameSixDigitCodeOnBothDevices() throws {
        var link = newLink()
        try link.start()

        let hostCode = try #require(link.hostEvents.compactMap(\.pairingCode).first)
        let controllerCode = try #require(link.controllerEvents.compactMap(\.pairingCode).first)
        #expect(hostCode == controllerCode)
        #expect(hostCode.count == 6 && hostCode.allSatisfy(\.isNumber))
        #expect(link.host.peer == PeerIdentity(instanceID: phone.instanceID, deviceName: "iPhone"))
        #expect(link.controller.peer == PeerIdentity(instanceID: mac.instanceID, deviceName: "Mac"))
        #expect(!link.host.isVerified && !link.controller.isVerified)
    }

    @Test(arguments: [true, false])
    func confirmingOnBothDevicesPairsAndVerifies(hostConfirmsFirst: Bool) throws {
        var link = newLink()
        try link.start()

        if hostConfirmsFirst {
            try link.confirmOnHost()
            #expect(link.hostEvents.compactMap(\.pairedKey).first == nil, "one confirmation is not enough")
            try link.confirmOnController()
        } else {
            try link.confirmOnController()
            #expect(link.controllerEvents.compactMap(\.pairedKey).first == nil, "one confirmation is not enough")
            try link.confirmOnHost()
        }

        let hostKey = try #require(link.hostEvents.compactMap(\.pairedKey).first)
        let controllerKey = try #require(link.controllerEvents.compactMap(\.pairedKey).first)
        #expect(hostKey.rawRepresentation == controllerKey.rawRepresentation)
        #expect(link.host.isVerified && link.controller.isVerified)
        #expect(link.hostEvents.contains { $0.isVerified } && link.controllerEvents.contains { $0.isVerified })
    }

    @Test func eachPairingProducesADifferentKey() throws {
        let first = try pair()
        let second = try pair()
        #expect(first.host.rawRepresentation != second.host.rawRepresentation)
    }

    @Test func rejectionOnOneDeviceEndsThePairingOnBoth() throws {
        var link = newLink()
        try link.start()
        let rejection = link.host.rejectPairingCode()

        #expect(throws: RemoteProtocolError.pairingRejectedByPeer) {
            try link.pump(toController: rejection.bytes)
        }
        #expect(link.hostEvents.compactMap(\.pairedKey).first == nil)
        #expect(throws: RemoteProtocolError.connectionClosed) {
            try link.host.confirmPairingCode()
        }
    }

    @Test func manInTheMiddleSeesDifferentCodes() throws {
        // The attacker runs a host towards the real controller and a controller towards the real host.
        let attacker = LocalIdentity(instanceID: InstanceID(), deviceName: "Mac")
        var towardsController = Link(
            host: HostConnection(local: attacker, trustedKey: untrusted),
            controller: ControllerConnection(local: phone, trustedKey: untrusted)
        )
        var towardsHost = Link(
            host: HostConnection(local: mac, trustedKey: untrusted),
            controller: ControllerConnection(local: attacker, trustedKey: untrusted)
        )
        try towardsController.start()
        try towardsHost.start()

        let controllerSees = try #require(towardsController.controllerEvents.compactMap(\.pairingCode).first)
        let hostSees = try #require(towardsHost.hostEvents.compactMap(\.pairingCode).first)
        // Equal only with a chance of 1 in 10^6, because each side committed before the other's nonce.
        #expect(controllerSees != hostSees)
    }

    @Test func revealNotMatchingTheCommitmentIsRejected() throws {
        var controller = ControllerConnection(local: phone, trustedKey: untrusted)
        _ = try controller.start()
        _ = try controller.receive(frame(hello(mac, role: .host)))

        let hostKey = Data(repeating: 9, count: 32)
        let committedNonce = Data(repeating: 1, count: 32)
        // The commitment covers the controller's key too; it is unknown here, so any reveal must fail.
        let commitment = RemoteCrypto.commitment(hostNonce: committedNonce, hostKey: hostKey, controllerKey: Data(count: 32))
        _ = try controller.receive(frame(.pairingCommit(publicKey: hostKey, commitment: commitment)))
        #expect(throws: RemoteProtocolError.commitmentMismatch) {
            try controller.receive(frame(.pairingReveal(committedNonce)))
        }
    }

    @Test func hostDoesNotSkipItsOwnConfirmation() throws {
        var link = newLink()
        try link.start()
        try link.confirmOnController()
        // A controller that jumps to authentication while the host user has not confirmed.
        #expect(throws: RemoteProtocolError.unexpectedMessage) {
            try link.host.receive(frame(.authenticate(nonce: Data(count: 32))))
        }
    }

    @Test func pairingKeyIsNotPrinted() throws {
        let key = try #require(PairingKey(rawRepresentation: Data(repeating: 7, count: 32)))
        #expect(!String(describing: key).contains("7"))
        #expect(PairingKey(rawRepresentation: Data(count: 16)) == nil)
    }
}

struct ReconnectTests {
    @Test func trustedDevicesReconnectWithoutCode() throws {
        let keys = try pair()
        var link = newLink(hostKey: keys.host, controllerKey: keys.controller)
        try link.start()

        #expect(link.hostEvents.compactMap(\.pairingCode).first == nil && link.controllerEvents.compactMap(\.pairingCode).first == nil)
        #expect(link.host.isVerified && link.controller.isVerified)
    }

    @Test func controllerPairsAgainWhenTheHostForgotIt() throws {
        let keys = try pair()
        var link = newLink(hostKey: nil, controllerKey: keys.controller)
        try link.start()

        #expect(link.controllerEvents.contains { $0.isPairingRequired })
        #expect(link.controllerEvents.compactMap(\.pairingCode).first == nil, "pairing waits for the user")
        try link.pump(toHost: link.controller.startPairing().bytes)
        #expect(link.controllerEvents.compactMap(\.pairingCode).first == link.hostEvents.compactMap(\.pairingCode).first)
        try link.confirmOnHost()
        try link.confirmOnController()
        #expect(link.host.isVerified && link.controller.isVerified)
    }

    @Test func forgedPairingRequiredOnReconnectOnlyAsks() throws {
        let keys = try pair()
        var controller = ControllerConnection(local: phone, trustedKey: { _ in keys.controller })
        _ = try controller.start()
        _ = try controller.receive(frame(hello(mac, role: .host)))
        let output = try controller.receive(frame(.pairingRequired))
        // No key is dropped and nothing is sent: the user decides.
        #expect(output.events.contains { $0.isPairingRequired })
        #expect(output.events.compactMap(\.pairedKey).isEmpty)
        #expect(output.bytes.isEmpty)
    }

    @Test func startPairingOnlyAfterPairingRequired() {
        var controller = ControllerConnection(local: phone, trustedKey: untrusted)
        #expect(throws: RemoteProtocolError.unexpectedMessage) {
            try controller.startPairing()
        }
    }

    @Test func hostPairsAgainWhenTheControllerForgotIt() throws {
        let keys = try pair()
        var link = newLink(hostKey: keys.host, controllerKey: nil)
        try link.start()
        #expect(link.hostEvents.compactMap(\.pairingCode).first != nil)
    }

    @Test func differentKeysFailAuthentication() throws {
        let first = try pair()
        let second = try pair()
        var link = newLink(hostKey: first.host, controllerKey: second.controller)
        #expect(throws: RemoteProtocolError.authenticationFailed) {
            try link.start()
        }
        let hostVerified = link.host.isVerified
        #expect(!hostVerified)
    }

    @Test func forgedPairingRequiredIsNotAcceptedAfterPairing() throws {
        var link = newLink()
        try link.start()
        try link.confirmOnHost()
        // Controller confirms last and sends `authenticate` with the fresh key; nothing delivered yet.
        _ = try link.controller.confirmPairingCode()
        #expect(throws: RemoteProtocolError.unexpectedMessage) {
            try link.controller.receive(frame(.pairingRequired))
        }
    }
}

struct VerifiedConnectionTests {
    private func verifiedLink() throws -> Link {
        let keys = try pair()
        var link = newLink(hostKey: keys.host, controllerKey: keys.controller)
        try link.start()
        return link
    }

    @Test func commandsReachTheHost() throws {
        var link = try verifiedLink()
        var bytes = Data()
        for message in MessageTests.controllerMessages {
            bytes += try link.controller.send(message)
        }
        try link.pump(toHost: bytes)
        #expect(link.hostEvents.compactMap(\.message) == MessageTests.controllerMessages)
    }

    @Test func hostOffersEveryOpenPresentation() throws {
        var link = try verifiedLink()
        let list = [
            PresentationSummary(id: PresentationID(), title: "Talk.pdf", slideCount: 12),
            PresentationSummary(id: PresentationID(), title: "Lecture.pdf", slideCount: 40),
        ]
        try link.pump(toController: link.host.send(.presentations(list)))
        #expect(link.controllerEvents.compactMap(\.message) == [HostMessage.presentations(list)])
    }

    @Test func contentFlowsToTheController() throws {
        var link = try verifiedLink()
        var bytes = Data()
        for message in MessageTests.hostMessages {
            bytes += try link.host.send(message)
        }
        try link.pump(toController: bytes)
        #expect(link.controllerEvents.compactMap(\.message) == MessageTests.hostMessages)
    }

    @Test func replayedFrameIsRejected() throws {
        var link = try verifiedLink()
        let frame = try link.controller.send(.nextSlide)
        try link.pump(toHost: frame)
        #expect(throws: RemoteProtocolError.authenticationFailed) {
            try link.pump(toHost: frame)
        }
        #expect(link.hostEvents.compactMap(\.message) == [ControllerMessage.nextSlide])
    }

    @Test func tooLargeMessageLeavesTheConnectionUsable() throws {
        var link = try verifiedLink()
        let huge = EncodedImage(format: .jpeg, pixelWidth: 1, pixelHeight: 1, data: Data(count: 13 * 1024 * 1024))
        let images = SlideImages(presentationID: PresentationID(), slideIndex: 0, current: huge, next: nil, notes: nil)
        #expect(throws: RemoteProtocolError.self) {
            try link.host.send(.slideImages(images))
        }
        try link.pump(toController: link.host.send(.presentationClosed(images.presentationID)))
        #expect(link.controllerEvents.compactMap(\.message) == [HostMessage.presentationClosed(images.presentationID)])
    }

    @Test func tamperedFrameIsRejected() throws {
        var link = try verifiedLink()
        var frame = try link.controller.send(.previousSlide)
        frame[frame.count - 1] ^= 0x01
        #expect(throws: RemoteProtocolError.authenticationFailed) {
            try link.pump(toHost: frame)
        }
    }
}

/// REM-06: unverified peers can neither control nor see a presentation (DEF-04 not replicated).
struct VerificationGateTests {
    @Test func hostSendsNoContentBeforeVerification() throws {
        var link = newLink()
        try link.start()
        #expect(throws: RemoteProtocolError.notVerified) {
            try link.host.send(.presentations([]))
        }
        #expect(throws: RemoteProtocolError.notVerified) {
            try link.controller.send(.nextSlide)
        }
    }

    @Test func clearTextCommandFromUnverifiedPeerHasNoEffect() throws {
        var host = HostConnection(local: mac, trustedKey: untrusted)
        _ = try host.start()
        _ = try host.receive(frame(hello(phone, role: .controller)))
        let command = try FrameEncoder.frame(ControllerMessage.nextSlide.wireData())
        let output = try host.receive(command)
        #expect(output.events.isEmpty)
        let verified = host.isVerified
        #expect(!verified)
    }

    @Test func randomBytesAsProofFail() throws {
        var host = HostConnection(local: mac, trustedKey: { _ in PairingKey(rawRepresentation: Data(repeating: 3, count: 32)) })
        _ = try host.start()
        _ = try host.receive(frame(hello(phone, role: .controller)))
        _ = try host.receive(frame(.authenticate(nonce: Data(count: 32))))
        #expect(throws: RemoteProtocolError.authenticationFailed) {
            try host.receive(frame(.authenticateProof(Data(count: 32))))
        }
    }
}

struct HelloTests {
    @Test func relayedHelloWithChangedNameFailsAuthentication() throws {
        let keys = try pair()
        var host = HostConnection(local: mac, trustedKey: { _ in keys.host })
        var controller = ControllerConnection(local: phone, trustedKey: { _ in keys.controller })
        let hostHello = try host.start().bytes
        _ = try controller.start()

        // A relay replaces the controller's hello with one carrying another device name.
        let forged = try frame(hello(LocalIdentity(instanceID: phone.instanceID, deviceName: "Trusted iPad"), role: .controller))
        _ = try host.receive(forged)
        let authenticate = try controller.receive(hostHello).bytes
        let response = try host.receive(authenticate).bytes
        #expect(throws: RemoteProtocolError.authenticationFailed) {
            try controller.receive(response)
        }
    }

    @Test func instanceNeverConnectsToItself() {
        var link = Link(
            host: HostConnection(local: mac, trustedKey: untrusted),
            controller: ControllerConnection(local: mac, trustedKey: untrusted)
        )
        #expect(throws: RemoteProtocolError.connectedToSelf) {
            try link.start()
        }
    }

    @Test func incompatibleVersionsFailOnBothSidesWithTheOutdatedSide() throws {
        var newer = HostConnection(local: mac, supportedVersions: 3...4, trustedKey: untrusted)
        var older = ControllerConnection(local: phone, supportedVersions: 1...2, trustedKey: untrusted)
        let newerHello = try newer.start().bytes
        let olderHello = try older.start().bytes

        #expect(throws: RemoteProtocolError.incompatibleVersion(VersionMismatch(local: 3...4, peer: 1...2))) {
            try newer.receive(olderHello)
        }
        #expect(throws: RemoteProtocolError.incompatibleVersion(VersionMismatch(local: 1...2, peer: 3...4))) {
            try older.receive(newerHello)
        }
    }

    @Test func overlappingVersionsUseTheHighestCommonOne() throws {
        var link = Link(
            host: HostConnection(local: mac, supportedVersions: 1...3, trustedKey: untrusted),
            controller: ControllerConnection(local: phone, supportedVersions: 2...5, trustedKey: untrusted)
        )
        try link.start()
        #expect(link.host.protocolVersion == 3)
        #expect(link.controller.protocolVersion == 3)
    }

    @Test func twoHostsDoNotTalk() throws {
        var host = HostConnection(local: mac, trustedKey: untrusted)
        _ = try host.start()
        #expect(throws: RemoteProtocolError.roleConflict) {
            try host.receive(frame(hello(phone, role: .host)))
        }
    }

    @Test func messagesBeforeStartOrDuplicateHelloAreRejected() throws {
        var host = HostConnection(local: mac, trustedKey: untrusted)
        _ = try host.start()
        #expect(throws: RemoteProtocolError.unexpectedMessage) {
            try host.start()
        }
        _ = try host.receive(frame(hello(phone, role: .controller)))
        #expect(throws: RemoteProtocolError.unexpectedMessage) {
            try host.receive(frame(hello(phone, role: .controller)))
        }
    }

    @Test func helloWithInvertedVersionRangeIsInvalid() throws {
        var host = HostConnection(local: mac, trustedKey: untrusted)
        _ = try host.start()
        let bad = HandshakeMessage.hello(Hello(minimumVersion: 2, version: 1, instanceID: phone.instanceID, deviceName: "x", role: .controller))
        #expect(throws: RemoteProtocolError.invalidMessage) {
            try host.receive(frame(bad))
        }
    }
}
