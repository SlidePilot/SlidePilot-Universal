import Foundation
import Testing
@testable import SlidePilotRemoteProtocol

/// One direction of an in-memory byte stream.
private actor Channel {
    private var buffer: [Data] = []
    private var isClosed = false
    private var waiter: CheckedContinuation<Data?, Never>?

    func push(_ bytes: Data) {
        guard !isClosed else { return }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: bytes)
        } else {
            buffer.append(bytes)
        }
    }

    func close() {
        isClosed = true
        waiter?.resume(returning: nil)
        waiter = nil
    }

    func pop() async -> Data? {
        if !buffer.isEmpty { return buffer.removeFirst() }
        if isClosed { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { await self.close() }
        }
    }
}

/// One end of an in-memory socket.
private struct PipeEnd: RemoteTransport {
    let inbox: Channel
    let outbox: Channel

    func send(_ bytes: Data) async throws { await outbox.push(bytes) }
    func receive() async throws -> Data? { await inbox.pop() }
}

private let mac = LocalIdentity(instanceID: InstanceID(), deviceName: "Mac")
private let pad = LocalIdentity(instanceID: InstanceID(), deviceName: "iPad")

private struct Outcome<Incoming: RemoteWireMessage>: Sendable {
    var events: [RemoteSessionEvent<Incoming>]
    var error: (any Error)?

    var protocolError: RemoteProtocolError? { error as? RemoteProtocolError }
    var codes: [String] { events.compactMap { if case .pairingCode(let code) = $0 { code } else { nil } } }
    var wasPaired: Bool { events.contains { if case .paired = $0 { true } else { false } } }
    var wasVerified: Bool { events.contains { if case .verified = $0 { true } else { false } } }
    var neededPairing: Bool { events.contains { if case .pairingRequiredByPeer = $0 { true } else { false } } }
    var lostTrust: Bool { events.contains { if case .trustRemovedByPeer = $0 { true } else { false } } }
    var messages: [Incoming] { events.compactMap { if case .message(let message) = $0 { message } else { nil } } }
}

/// Runs a session to its end, reacting to each event, then closes its side of the socket
/// like the app does.
private func drive<Outgoing, Incoming>(
    _ session: RemoteSession<Outgoing, Incoming>,
    closing outbox: Channel,
    onEvent: @escaping @Sendable (RemoteSessionEvent<Incoming>, RemoteSession<Outgoing, Incoming>) async -> Void
) async -> Outcome<Incoming> {
    async let runError = runCatchingError(session)
    var events: [RemoteSessionEvent<Incoming>] = []
    for await event in session.events {
        events.append(event)
        await onEvent(event, session)
    }
    let error = await runError
    await outbox.close()
    return Outcome(events: events, error: error)
}

private func runCatchingError<O, I>(_ session: RemoteSession<O, I>) async -> (any Error)? {
    do {
        try await session.run()
        return nil
    } catch {
        return error
    }
}

/// A host on the Mac and a controller on the iPad, wired back to back.
private struct Pair {
    let hostStore = InMemoryTrustStore()
    let controllerStore = InMemoryTrustStore()

    func run(
        host onHostEvent: @escaping @Sendable (HostSession.Event, HostSession) async -> Void,
        controller onControllerEvent: @escaping @Sendable (ControllerSession.Event, ControllerSession) async -> Void
    ) async -> (host: Outcome<ControllerMessage>, controller: Outcome<HostMessage>) {
        // A new socket per run.
        let toHost = Channel()
        let toController = Channel()
        let host = HostSession(local: mac, transport: PipeEnd(inbox: toHost, outbox: toController), trustStore: hostStore)
        let controller = ControllerSession(local: pad, transport: PipeEnd(inbox: toController, outbox: toHost), trustStore: controllerStore)
        async let hostOutcome = drive(host, closing: toController, onEvent: onHostEvent)
        async let controllerOutcome = drive(controller, closing: toHost, onEvent: onControllerEvent)
        return await (hostOutcome, controllerOutcome)
    }
}

/// Confirms every pairing code.
private func confirmCodes<O, I>(_ event: RemoteSessionEvent<I>, _ session: RemoteSession<O, I>) async {
    if case .pairingCode = event { try? await session.confirmPairingCode() }
}

/// Confirms codes and closes the session once it is verified.
private func confirmAndCloseWhenVerified<O, I>(_ event: RemoteSessionEvent<I>, _ session: RemoteSession<O, I>) async {
    await confirmCodes(event, session)
    if case .verified = event { await session.close() }
}

/// Pairs a fresh pair of stores.
private func pairedStores() async -> Pair {
    let pair = Pair()
    _ = await pair.run(host: confirmCodes, controller: confirmAndCloseWhenVerified)
    return pair
}

@Suite("Remote session", .timeLimit(.minutes(1)))
struct SessionTests {
    @Test("Pairing shows the same code on both devices and stores the key on both (REM-02)")
    func pairing() async {
        let pair = Pair()
        let (host, controller) = await pair.run(host: confirmCodes, controller: confirmAndCloseWhenVerified)

        #expect(host.error == nil, "\(String(describing: host.error))")
        #expect(controller.error == nil, "\(String(describing: controller.error))")
        #expect(host.codes.count == 1)
        #expect(host.codes == controller.codes)
        #expect(host.wasPaired && controller.wasPaired)
        #expect(host.wasVerified && controller.wasVerified)
        let hostKey = pair.hostStore.key(for: pad.instanceID)?.rawRepresentation
        #expect(hostKey != nil)
        #expect(hostKey == pair.controllerStore.key(for: mac.instanceID)?.rawRepresentation)
        #expect(pair.hostStore.devices().map(\.deviceName) == ["iPad"])
        #expect(pair.controllerStore.devices().map(\.deviceName) == ["Mac"])
    }

    @Test("Trusted devices reconnect without a code (REM-02)")
    func reconnect() async {
        let pair = await pairedStores()
        let (host, controller) = await pair.run(host: confirmCodes, controller: confirmAndCloseWhenVerified)

        #expect(host.codes.isEmpty && controller.codes.isEmpty)
        #expect(host.wasVerified && controller.wasVerified)
        #expect(host.error == nil && controller.error == nil)
    }

    @Test("A rejected code ends both sides without trust")
    func rejection() async {
        let pair = Pair()
        let (host, controller) = await pair.run(
            host: { event, session in
                if case .pairingCode = event { await session.rejectPairingCode() }
            },
            controller: { _, _ in }
        )

        #expect(controller.protocolError == .pairingRejectedByPeer)
        #expect(!host.wasPaired && !controller.wasPaired)
        #expect(pair.hostStore.devices().isEmpty)
        #expect(pair.controllerStore.devices().isEmpty)
    }

    @Test("A code confirmed on one device only does not create trust (REM-06)")
    func oneSidedConfirmation() async {
        let pair = Pair()
        let (host, controller) = await pair.run(
            // The host user never answers; the controller user confirms, then gives up.
            host: { _, _ in },
            controller: { event, session in
                if case .pairingCode = event {
                    try? await session.confirmPairingCode()
                    await session.rejectPairingCode()
                }
            }
        )

        #expect(!host.wasVerified && !controller.wasVerified)
        #expect(pair.hostStore.devices().isEmpty)
        #expect(pair.controllerStore.devices().isEmpty)
    }

    @Test("A host that forgot the controller asks it to pair again")
    func pairingRequired() async throws {
        let pair = await pairedStores()
        try pair.hostStore.removeTrust(for: pad.instanceID)

        let (host, controller) = await pair.run(
            host: confirmCodes,
            controller: { event, session in
                if case .pairingRequiredByPeer = event { try? await session.startPairing() }
                await confirmAndCloseWhenVerified(event, session)
            }
        )

        #expect(controller.neededPairing)
        #expect(host.codes.count == 1 && host.codes == controller.codes)
        #expect(host.wasVerified && controller.wasVerified)
        #expect(pair.hostStore.key(for: pad.instanceID) != nil)
    }

    @Test("Commands and content flow only after verification (REM-06)")
    func verifiedMessages() async {
        let pair = Pair()
        let (host, controller) = await pair.run(
            host: { event, session in
                if case .peerIdentified = event {
                    await #expect(throws: RemoteProtocolError.notVerified) { try await session.send(.trustRemoved) }
                }
                await confirmCodes(event, session)
                if case .verified = event { try? await session.send(.presentations([])) }
            },
            controller: { event, session in
                await confirmCodes(event, session)
                if case .verified = event { try? await session.send(.nextSlide) }
                if case .message = event { await session.close() }
            }
        )

        #expect(host.messages == [.nextSlide])
        #expect(controller.messages == [.presentations([])])
    }

    @Test("Removing trust on the host removes it on the controller too (REM-03)")
    func removeTrust() async {
        let pair = await pairedStores()
        let (host, controller) = await pair.run(
            host: { event, session in
                if case .verified = event { try? await session.removeTrustAndClose() }
            },
            controller: { _, _ in }
        )

        #expect(host.error == nil)
        #expect(controller.error == nil)
        #expect(controller.lostTrust)
        #expect(pair.hostStore.devices().isEmpty)
        #expect(pair.controllerStore.devices().isEmpty)
    }

    @Test("Trust is removed on the controller only through a verified session (DEF-04)")
    func unverifiedTrustRemoval() async {
        let pair = await pairedStores()
        let (host, controller) = await pair.run(
            host: { event, session in
                if case .peerIdentified = event { try? await session.removeTrustAndClose() }
            },
            controller: { _, _ in }
        )

        #expect(!host.wasVerified)
        #expect(!controller.lostTrust)
        // The host forgot the controller itself, but the controller keeps its key.
        #expect(pair.controllerStore.key(for: mac.instanceID) != nil)
    }

    @Test("Sending after the session ended fails")
    func sendAfterEnd() async {
        let pair = await pairedStores()
        let session = ControllerSession(
            local: pad,
            transport: PipeEnd(inbox: Channel(), outbox: Channel()),
            trustStore: pair.controllerStore
        )
        await session.close()
        try? await session.run()
        await #expect(throws: RemoteProtocolError.connectionClosed) { try await session.send(.nextSlide) }
    }
}

@Suite("Trust store")
struct TrustStoreTests {
    @Test("Devices are sorted by name, replaced on re-pairing and removable")
    func inMemory() throws {
        let store = InMemoryTrustStore()
        let key = try #require(PairingKey(rawRepresentation: Data(repeating: 1, count: 32)))
        let newKey = try #require(PairingKey(rawRepresentation: Data(repeating: 2, count: 32)))
        let zed = TrustedDevice(instanceID: InstanceID(), deviceName: "Zed", pairedAt: .now)
        let anna = TrustedDevice(instanceID: InstanceID(), deviceName: "anna", pairedAt: .now)

        try store.trust(zed, key: key)
        try store.trust(anna, key: key)
        try store.trust(zed, key: newKey)
        #expect(store.devices().map(\.deviceName) == ["anna", "Zed"])
        #expect(store.key(for: zed.instanceID)?.rawRepresentation == newKey.rawRepresentation)

        try store.removeTrust(for: zed.instanceID)
        try store.removeTrust(for: zed.instanceID)
        #expect(store.devices() == [anna])
        #expect(store.key(for: zed.instanceID) == nil)
    }
}
