import Foundation

/// A byte stream to one peer, e.g. a TCP connection. The app wraps its sockets in it; tests
/// use an in-memory pipe.
public protocol RemoteTransport: Sendable {
    /// Writes bytes. Calls never overlap: the session waits for each write.
    func send(_ bytes: Data) async throws
    /// The next bytes from the peer, or `nil` when the peer closed the stream.
    func receive() async throws -> Data?
}

/// The host side of a session: sends `HostMessage`, receives `ControllerMessage`.
public typealias HostSession = RemoteSession<HostMessage, ControllerMessage>
/// The controller side of a session: sends `ControllerMessage`, receives `HostMessage`.
public typealias ControllerSession = RemoteSession<ControllerMessage, HostMessage>

/// What happened on a session, in order.
public enum RemoteSessionEvent<Incoming: RemoteWireMessage>: Sendable {
    /// The peer's `hello` was accepted.
    case peerIdentified(PeerIdentity)
    /// Show this code and let the user confirm or reject it.
    case pairingCode(String)
    /// Both users confirmed the code; the key is in the trust store.
    case paired(PeerIdentity)
    /// The host does not trust this controller (any more). Call `startPairing()` only when
    /// the user asks to connect.
    case pairingRequiredByPeer(PeerIdentity)
    /// The peer proved the pairing key; messages can flow now (REM-06).
    case verified(PeerIdentity)
    case message(Incoming)
    /// Controller: the host removed its trust (REM-03); the local key is deleted too and
    /// the session ends.
    case trustRemovedByPeer(PeerIdentity)
}

/// Runs one connection (ADR 0017) over a transport: feeds received bytes to the protocol
/// state machine, writes its output in order, stores pairing keys and reports events.
///
/// The connection state lives only in this actor, so the encryption counters are never
/// shared. Every frame is queued for writing at the moment the state machine produces it,
/// and one writer task sends the queue in that order. Reentrant calls (a confirmation while
/// a frame is being handled) therefore cannot reorder frames.
public actor RemoteSession<Outgoing: RemoteWireMessage, Incoming: RemoteWireMessage> {
    public typealias Event = RemoteSessionEvent<Incoming>

    /// Ends when the session ends. Iterate it once.
    public nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation

    private enum Input: Sendable {
        case received(Data)
        case peerClosed
        case transportFailed(any Error)
        /// The writer sent everything queued before `close()`.
        case writesFlushed
    }

    private let inputs: AsyncStream<Input>
    private let inputContinuation: AsyncStream<Input>.Continuation
    /// Frames to write, in the order they were produced.
    private let writes: AsyncStream<Data>
    private let writeContinuation: AsyncStream<Data>.Continuation

    private var connection: RemoteConnection<Outgoing, Incoming>
    private let transport: any RemoteTransport
    private let trustStore: any TrustStore
    private var hasStarted = false
    private var hasEnded = false

    public private(set) var peer: PeerIdentity?
    public var isVerified: Bool { connection.isVerified }

    public init(local: LocalIdentity, transport: any RemoteTransport, trustStore: any TrustStore) {
        self.transport = transport
        self.trustStore = trustStore
        connection = RemoteConnection(local: local, trustedKey: { [trustStore] in trustStore.key(for: $0) })
        (events, eventContinuation) = AsyncStream.makeStream()
        (inputs, inputContinuation) = AsyncStream.makeStream()
        (writes, writeContinuation) = AsyncStream.makeStream()
    }

    /// Runs the session until the peer closes it, `close()` is called, an error ends it or
    /// the calling task is cancelled. Call once; the owner closes the socket afterwards.
    /// Throws `RemoteProtocolError` or the transport's error.
    public func run() async throws {
        guard !hasStarted else { throw RemoteProtocolError.connectionClosed }
        hasStarted = true
        defer { end() }

        let transport = transport
        let inputs = inputContinuation
        let writes = writes
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Reader and writer only move bytes; all state changes happen in `process()`.
            group.addTask {
                do {
                    while let bytes = try await transport.receive() {
                        inputs.yield(.received(bytes))
                    }
                    inputs.yield(.peerClosed)
                } catch {
                    inputs.yield(.transportFailed(error))
                }
            }
            group.addTask {
                do {
                    for await bytes in writes {
                        try await transport.send(bytes)
                    }
                    inputs.yield(.writesFlushed)
                } catch {
                    inputs.yield(.transportFailed(error))
                }
            }
            defer {
                // Event consumers see the end right away, before the reader is cancelled.
                eventContinuation.finish()
                group.cancelAll()
            }
            try await process()
        }
    }

    private func process() async throws {
        enqueue(try connection.start().bytes)
        // Ends without an error when the calling task is cancelled.
        for await input in inputs {
            switch input {
            case .received(let bytes):
                guard !hasEnded else { continue }
                let output = try connection.receive(bytes)
                enqueue(output.bytes)
                if try handle(output.events) == .end { close() }
            case .writesFlushed, .peerClosed:
                return
            case .transportFailed(let error):
                throw error
            }
        }
    }

    // MARK: - User actions

    /// The local user confirmed that both devices show the same code.
    public func confirmPairingCode() throws {
        guard !hasEnded else { throw RemoteProtocolError.connectionClosed }
        do {
            let output = try connection.confirmPairingCode()
            enqueue(output.bytes)
            if try handle(output.events) == .end { close() }
        } catch {
            // The connection is unusable after an error.
            close()
            throw error
        }
    }

    /// The local user rejected the code, or this instance does not accept pairing now.
    /// Ends the session.
    public func rejectPairingCode() {
        guard !hasEnded else { return }
        enqueue(connection.rejectPairingCode().bytes)
        close()
    }

    /// Controller: pairs again after `.pairingRequiredByPeer`, when the user asks for it.
    public func startPairing() throws {
        guard !hasEnded else { throw RemoteProtocolError.connectionClosed }
        do {
            enqueue(try connection.startPairing().bytes)
        } catch {
            close()
            throw error
        }
    }

    /// Encrypts a message for the verified peer (REM-06: throws `notVerified` before).
    public func send(_ message: Outgoing) throws {
        guard !hasEnded else { throw RemoteProtocolError.connectionClosed }
        enqueue(try connection.send(message))
    }

    /// Ends the session after the queued writes. Takes effect right away: frames received
    /// afterwards are ignored and nothing more is sent.
    public func close() {
        hasEnded = true
        writeContinuation.finish()
    }

    // MARK: - Internals

    private enum Flow { case proceed, end }

    private func handle(_ events: [RemoteConnection<Outgoing, Incoming>.Event]) throws -> Flow {
        for event in events {
            switch event {
            case .peerIdentified(let peer):
                self.peer = peer
                eventContinuation.yield(.peerIdentified(peer))
            case .pairingCode(let code):
                eventContinuation.yield(.pairingCode(code))
            case .paired(let peer, let key):
                try trustStore.trust(TrustedDevice(instanceID: peer.instanceID, deviceName: peer.deviceName, pairedAt: .now), key: key)
                eventContinuation.yield(.paired(peer))
            case .pairingRequiredByPeer(let peer):
                eventContinuation.yield(.pairingRequiredByPeer(peer))
            case .verified(let peer, _):
                eventContinuation.yield(.verified(peer))
            case .message(let message):
                // Only a verified host can send this (it arrives encrypted), so a stranger
                // cannot remove trust (DEF-04).
                if let hostMessage = message as? HostMessage, hostMessage == .trustRemoved, let peer {
                    try trustStore.removeTrust(for: peer.instanceID)
                    eventContinuation.yield(.trustRemovedByPeer(peer))
                    return .end
                }
                eventContinuation.yield(.message(message))
            }
        }
        return .proceed
    }

    /// Queues frames right when the state machine produced them, so they keep that order.
    private func enqueue(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        writeContinuation.yield(bytes)
    }

    private func end() {
        hasEnded = true
        eventContinuation.finish()
        inputContinuation.finish()
        writeContinuation.finish()
    }
}

extension RemoteSession where Outgoing == HostMessage {
    /// Host: forgets the controller and ends the session (REM-03). A verified controller is
    /// told first, so it deletes its key and stops reconnecting.
    public func removeTrustAndClose() throws {
        defer { close() }
        if let peer {
            try trustStore.removeTrust(for: peer.instanceID)
        }
        if connection.isVerified {
            try? send(.trustRemoved)
        }
    }
}
