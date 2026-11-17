import CryptoKit
import Foundation

/// The host side of one connection: sends `HostMessage`, receives `ControllerMessage`.
public typealias HostConnection = RemoteConnection<HostMessage, ControllerMessage>
/// The controller side of one connection: sends `ControllerMessage`, receives `HostMessage`.
public typealias ControllerConnection = RemoteConnection<ControllerMessage, HostMessage>

/// The protocol state of one connection (ADR 0017), without sockets: the app writes
/// `Output.bytes` to the socket and passes received bytes to `receive(_:)`.
///
/// Before the peer is verified only handshake messages are accepted; commands and content
/// exist only as encrypted frames afterwards (REM-06). An error thrown by `receive(_:)`,
/// `confirmPairingCode()` or `startPairing()` ends the connection, and the output of frames
/// already handled in the same call is dropped with it. `send(_:)` errors leave it usable.
///
/// Not copyable: it holds the encryption counters, and a copy that sends would reuse a nonce.
/// Keep it in the owning actor's stored property and mutate it in place; never copy it across
/// an `await`.
public struct RemoteConnection<Outgoing: RemoteWireMessage, Incoming: RemoteWireMessage>: ~Copyable, Sendable {
    public enum Event: Sendable {
        /// The peer's `hello` was accepted.
        case peerIdentified(PeerIdentity)
        /// Show this code and ask the user to confirm it matches the peer's.
        case pairingCode(String)
        /// Both users confirmed the code: store the key for this peer in the Keychain.
        case paired(PeerIdentity, PairingKey)
        /// The host asks for a new pairing. The message is not authenticated, so keep any
        /// stored key until `.paired` replaces it, and call `startPairing()` only when the user
        /// asks to connect.
        case pairingRequiredByPeer(PeerIdentity)
        /// The peer proved the pairing key; messages can flow now.
        case verified(PeerIdentity, protocolVersion: Int)
        case message(Incoming)
    }

    public struct Output: Sendable {
        /// Framed bytes to write to the socket, in order.
        public internal(set) var bytes = Data()
        public internal(set) var events: [Event] = []

        mutating func send(_ message: HandshakeMessage) throws(RemoteProtocolError) {
            bytes.append(try FrameEncoder.frame(try message.wireData()))
        }
    }

    /// Looks up the stored pairing key for a peer. It runs synchronously inside `receive(_:)`,
    /// so back it with a synchronous Keychain read on the connection's actor, not with a
    /// main-actor store.
    public typealias TrustLookup = @Sendable (InstanceID) -> PairingKey?

    private enum Phase: Sendable {
        case notStarted
        case awaitingHello
        // Host
        case awaitingController
        case awaitingPairingNonce(privateKey: Data, controllerKey: Data, hostNonce: Data)
        case awaitingAuthenticationProof(RemoteCrypto.SessionKeys)
        // Controller
        case awaitingPairingCommit(privateKey: Data)
        case awaitingPairingReveal(privateKey: Data, hostKey: Data, commitment: Data, controllerNonce: Data)
        case awaitingAuthenticationResponse(PairingKey, controllerNonce: Data, usesStoredKey: Bool)
        case awaitingPairingStart
        // Both
        case confirmingPairing(key: PairingKey, localConfirmed: Bool, peerConfirmed: Bool)
        case verified(SecureChannel)
        case failed
    }

    public var role: RemoteRole { Outgoing.sender }
    public private(set) var peer: PeerIdentity?
    public private(set) var protocolVersion: Int?

    private let local: LocalIdentity
    private let trustedKey: TrustLookup
    private let supportedVersions: ClosedRange<Int>
    private var phase = Phase.notStarted
    private var frames = FrameDecoder()
    /// Host: the key paired on this connection, used before the app has stored it.
    private var pairedKey: PairingKey?
    /// The exact `hello` payloads, bound into pairing and authentication so a relay cannot
    /// change names, roles or versions unnoticed.
    private var localHello = Data()
    private var peerHello = Data()

    public init(local: LocalIdentity, trustedKey: @escaping TrustLookup) {
        self.init(local: local, supportedVersions: ProtocolVersion.supported, trustedKey: trustedKey)
    }

    /// `supportedVersions` lets tests simulate other app versions.
    init(local: LocalIdentity, supportedVersions: ClosedRange<Int>, trustedKey: @escaping TrustLookup) {
        precondition(Incoming.sender == Outgoing.sender.opposite, "Incoming must be sent by the other role")
        self.local = local
        self.supportedVersions = supportedVersions
        self.trustedKey = trustedKey
    }

    public var isVerified: Bool {
        if case .verified = phase { true } else { false }
    }

    /// Sends `hello`. Call once, right after the socket connects.
    public mutating func start() throws(RemoteProtocolError) -> Output {
        guard case .notStarted = phase else { throw .unexpectedMessage }
        let hello = try HandshakeMessage.hello(Hello(
            minimumVersion: supportedVersions.lowerBound,
            version: supportedVersions.upperBound,
            instanceID: local.instanceID,
            deviceName: local.deviceName,
            role: role
        )).wireData()
        var output = Output()
        output.bytes = try FrameEncoder.frame(hello)
        localHello = hello
        phase = .awaitingHello
        return output
    }

    /// Feeds bytes from the socket.
    public mutating func receive(_ bytes: Data) throws(RemoteProtocolError) -> Output {
        try failingOnError { (connection: inout Self) throws(RemoteProtocolError) in
            connection.frames.append(bytes)
            var output = Output()
            while let frame = try connection.frames.nextFrame() {
                try connection.handle(frame, into: &output)
            }
            return output
        }
    }

    /// The local user confirmed that both devices show the same code.
    public mutating func confirmPairingCode() throws(RemoteProtocolError) -> Output {
        try failingOnError { (connection: inout Self) throws(RemoteProtocolError) in
            guard case .confirmingPairing(let key, false, let peerConfirmed) = connection.phase else {
                throw .unexpectedMessage
            }
            var output = Output()
            try output.send(.pairingConfirmed)
            try connection.finishPairing(key: key, localConfirmed: true, peerConfirmed: peerConfirmed, into: &output)
            return output
        }
    }

    /// The local user rejected the code. Write the returned bytes, then close the connection.
    public mutating func rejectPairingCode() -> Output {
        var output = Output()
        if case .confirmingPairing = phase {
            try? output.send(.pairingRejected)
        }
        phase = .failed
        return output
    }

    /// Controller: starts pairing after `.pairingRequiredByPeer`, when the user asks for it.
    public mutating func startPairing() throws(RemoteProtocolError) -> Output {
        try failingOnError { (connection: inout Self) throws(RemoteProtocolError) in
            guard case .awaitingPairingStart = connection.phase else { throw .unexpectedMessage }
            var output = Output()
            try connection.startPairing(into: &output)
            return output
        }
    }

    /// Encrypts a message for the verified peer; returns framed bytes for the socket.
    /// A message too large for one frame throws `frameTooLarge` and leaves the connection
    /// usable, so the app can send a smaller rendition instead.
    public mutating func send(_ message: Outgoing) throws(RemoteProtocolError) -> Data {
        if case .failed = phase { throw .connectionClosed }
        guard case .verified(var channel) = phase else { throw .notVerified }
        let plaintext = try message.wireData()
        let sealedCount = plaintext.count + SecureChannel.tagByteCount
        guard sealedCount <= FrameDecoder.maximumFrameLength else { throw .frameTooLarge(sealedCount) }
        let framed = try FrameEncoder.frame(try channel.seal(plaintext))
        phase = .verified(channel)
        return framed
    }

    // MARK: - Handling

    private mutating func failingOnError<T>(_ body: (inout Self) throws(RemoteProtocolError) -> T) throws(RemoteProtocolError) -> T {
        if case .failed = phase { throw .connectionClosed }
        do {
            return try body(&self)
        } catch {
            phase = .failed
            throw error
        }
    }

    private mutating func handle(_ frame: Data, into output: inout Output) throws(RemoteProtocolError) {
        if case .verified(var channel) = phase {
            let plaintext = try channel.open(frame)
            phase = .verified(channel)
            if let message = try Incoming.fromWire(plaintext) {
                output.events.append(.message(message))
            }
            return
        }
        guard let message = try HandshakeMessage.fromWire(frame) else { return }
        if case .hello = message, case .awaitingHello = phase { peerHello = frame }
        try handle(message, into: &output)
    }

    private mutating func handle(_ message: HandshakeMessage, into output: inout Output) throws(RemoteProtocolError) {
        switch (phase, message) {
        case (.awaitingHello, .hello(let hello)):
            try accept(hello, into: &output)

        case (_, .pairingRejected):
            throw .pairingRejectedByPeer

        // Host
        case (.awaitingController, .pairingStart(let controllerKey)):
            try Self.check(controllerKey, count: RemoteCrypto.publicKeyByteCount)
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let hostKey = privateKey.publicKey.rawRepresentation
            let hostNonce = RemoteCrypto.randomBytes()
            let commitment = RemoteCrypto.commitment(hostNonce: hostNonce, hostKey: hostKey, controllerKey: controllerKey)
            try output.send(.pairingCommit(publicKey: hostKey, commitment: commitment))
            phase = .awaitingPairingNonce(privateKey: privateKey.rawRepresentation, controllerKey: controllerKey, hostNonce: hostNonce)

        case (.awaitingPairingNonce(let privateKeyData, let controllerKey, let hostNonce), .pairingNonce(let controllerNonce)):
            try Self.check(controllerNonce, count: RemoteCrypto.nonceByteCount)
            try output.send(.pairingReveal(hostNonce))
            let privateKey = try Self.privateKey(privateKeyData)
            let transcript = RemoteCrypto.PairingTranscript(
                controllerKey: controllerKey,
                hostKey: privateKey.publicKey.rawRepresentation,
                controllerNonce: controllerNonce,
                hostNonce: hostNonce,
                controllerID: try requirePeer().instanceID,
                hostID: local.instanceID,
                helloDigest: helloDigest
            )
            try beginConfirmation(transcript, privateKey: privateKey, peerKey: controllerKey, into: &output)

        case (.awaitingController, .authenticate(let controllerNonce)):
            try Self.check(controllerNonce, count: RemoteCrypto.nonceByteCount)
            let peer = try requirePeer()
            guard let key = pairedKey ?? trustedKey(peer.instanceID) else {
                try output.send(.pairingRequired)
                return
            }
            let hostNonce = RemoteCrypto.randomBytes()
            let keys = RemoteCrypto.SessionKeys(
                pairingKey: key,
                controllerNonce: controllerNonce,
                hostNonce: hostNonce,
                controllerID: peer.instanceID,
                hostID: local.instanceID,
                helloDigest: helloDigest
            )
            try output.send(.authenticateResponse(nonce: hostNonce, proof: keys.proof(by: .host)))
            phase = .awaitingAuthenticationProof(keys)

        case (.awaitingAuthenticationProof(let keys), .authenticateProof(let proof)):
            guard keys.isValid(proof: proof, by: .controller) else { throw .authenticationFailed }
            try becomeVerified(keys, into: &output)

        // Controller
        case (.awaitingPairingCommit(let privateKey), .pairingCommit(let hostKey, let commitment)):
            try Self.check(hostKey, count: RemoteCrypto.publicKeyByteCount)
            try Self.check(commitment, count: SHA256.byteCount)
            let controllerNonce = RemoteCrypto.randomBytes()
            try output.send(.pairingNonce(controllerNonce))
            phase = .awaitingPairingReveal(privateKey: privateKey, hostKey: hostKey, commitment: commitment, controllerNonce: controllerNonce)

        case (.awaitingPairingReveal(let privateKeyData, let hostKey, let commitment, let controllerNonce), .pairingReveal(let hostNonce)):
            try Self.check(hostNonce, count: RemoteCrypto.nonceByteCount)
            let privateKey = try Self.privateKey(privateKeyData)
            let controllerKey = privateKey.publicKey.rawRepresentation
            guard RemoteCrypto.commitment(hostNonce: hostNonce, hostKey: hostKey, controllerKey: controllerKey) == commitment else {
                throw .commitmentMismatch
            }
            let transcript = RemoteCrypto.PairingTranscript(
                controllerKey: controllerKey,
                hostKey: hostKey,
                controllerNonce: controllerNonce,
                hostNonce: hostNonce,
                controllerID: local.instanceID,
                hostID: try requirePeer().instanceID,
                helloDigest: helloDigest
            )
            try beginConfirmation(transcript, privateKey: privateKey, peerKey: hostKey, into: &output)

        case (.awaitingAuthenticationResponse(let key, let controllerNonce, _), .authenticateResponse(let hostNonce, let proof)):
            try Self.check(hostNonce, count: RemoteCrypto.nonceByteCount)
            let keys = RemoteCrypto.SessionKeys(
                pairingKey: key,
                controllerNonce: controllerNonce,
                hostNonce: hostNonce,
                controllerID: local.instanceID,
                hostID: try requirePeer().instanceID,
                helloDigest: helloDigest
            )
            guard keys.isValid(proof: proof, by: .host) else { throw .authenticationFailed }
            try output.send(.authenticateProof(keys.proof(by: .controller)))
            try becomeVerified(keys, into: &output)

        case (.awaitingAuthenticationResponse(_, _, usesStoredKey: true), .pairingRequired):
            output.events.append(.pairingRequiredByPeer(try requirePeer()))
            phase = .awaitingPairingStart

        // Both
        case (.confirmingPairing(let key, let localConfirmed, false), .pairingConfirmed):
            try finishPairing(key: key, localConfirmed: localConfirmed, peerConfirmed: true, into: &output)

        default:
            throw .unexpectedMessage
        }
    }

    private mutating func accept(_ hello: Hello, into output: inout Output) throws(RemoteProtocolError) {
        guard hello.instanceID != local.instanceID else { throw .connectedToSelf }
        guard let peerVersions = hello.versions else { throw .invalidMessage }
        guard let version = ProtocolVersion.negotiate(local: supportedVersions, peer: peerVersions) else {
            throw .incompatibleVersion(VersionMismatch(local: supportedVersions, peer: peerVersions))
        }
        guard hello.role == role.opposite else { throw .roleConflict }

        let peer = PeerIdentity(instanceID: hello.instanceID, deviceName: hello.deviceName)
        self.peer = peer
        protocolVersion = version
        output.events.append(.peerIdentified(peer))

        switch role {
        case .host:
            phase = .awaitingController
        case .controller:
            if let key = trustedKey(peer.instanceID) {
                try startAuthentication(with: key, usesStoredKey: true, into: &output)
            } else {
                try startPairing(into: &output)
            }
        }
    }

    private mutating func startPairing(into output: inout Output) throws(RemoteProtocolError) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        try output.send(.pairingStart(publicKey: privateKey.publicKey.rawRepresentation))
        phase = .awaitingPairingCommit(privateKey: privateKey.rawRepresentation)
    }

    private mutating func startAuthentication(with key: PairingKey, usesStoredKey: Bool, into output: inout Output) throws(RemoteProtocolError) {
        let nonce = RemoteCrypto.randomBytes()
        try output.send(.authenticate(nonce: nonce))
        phase = .awaitingAuthenticationResponse(key, controllerNonce: nonce, usesStoredKey: usesStoredKey)
    }

    private mutating func beginConfirmation(
        _ transcript: RemoteCrypto.PairingTranscript,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerKey: Data,
        into output: inout Output
    ) throws(RemoteProtocolError) {
        let key = try transcript.pairingKey(privateKey: privateKey, peerKey: peerKey)
        phase = .confirmingPairing(key: key, localConfirmed: false, peerConfirmed: false)
        output.events.append(.pairingCode(transcript.code))
    }

    private mutating func finishPairing(key: PairingKey, localConfirmed: Bool, peerConfirmed: Bool, into output: inout Output) throws(RemoteProtocolError) {
        guard localConfirmed, peerConfirmed else {
            phase = .confirmingPairing(key: key, localConfirmed: localConfirmed, peerConfirmed: peerConfirmed)
            return
        }
        output.events.append(.paired(try requirePeer(), key))
        switch role {
        case .host:
            pairedKey = key
            phase = .awaitingController
        case .controller:
            try startAuthentication(with: key, usesStoredKey: false, into: &output)
        }
    }

    private mutating func becomeVerified(_ keys: RemoteCrypto.SessionKeys, into output: inout Output) throws(RemoteProtocolError) {
        phase = .verified(keys.channel(for: role))
        output.events.append(.verified(try requirePeer(), protocolVersion: protocolVersion ?? ProtocolVersion.current))
    }

    /// Both `hello` payloads, controller first.
    private var helloDigest: Data {
        role == .controller ? RemoteCrypto.sha256(localHello, peerHello) : RemoteCrypto.sha256(peerHello, localHello)
    }

    private func requirePeer() throws(RemoteProtocolError) -> PeerIdentity {
        guard let peer else { throw .unexpectedMessage }
        return peer
    }

    private static func check(_ data: Data, count: Int) throws(RemoteProtocolError) {
        guard data.count == count else { throw .invalidMessage }
    }

    private static func privateKey(_ data: Data) throws(RemoteProtocolError) -> Curve25519.KeyAgreement.PrivateKey {
        do {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        } catch {
            throw .invalidMessage
        }
    }
}
