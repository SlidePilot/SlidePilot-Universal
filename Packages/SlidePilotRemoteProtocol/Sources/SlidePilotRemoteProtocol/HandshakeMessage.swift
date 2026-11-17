import Foundation

/// The first message of every connection, in clear text. Its shape never changes, so any
/// two versions can tell each other they are incompatible (ADR 0017).
struct Hello: Codable, Sendable, Equatable {
    let minimumVersion: Int
    let version: Int
    let instanceID: InstanceID
    let deviceName: String
    let role: RemoteRole

    var versions: ClosedRange<Int>? {
        minimumVersion <= version ? minimumVersion...version : nil
    }
}

/// Clear-text messages before the peer is verified. Nothing in here controls a
/// presentation or reveals its content (REM-06).
enum HandshakeMessage: Sendable, Equatable {
    case hello(Hello)
    /// Controller → host: ephemeral X25519 public key.
    case pairingStart(publicKey: Data)
    /// Host → controller: ephemeral public key and commitment to its nonce.
    case pairingCommit(publicKey: Data, commitment: Data)
    /// Controller → host.
    case pairingNonce(Data)
    /// Host → controller: the nonce committed to before.
    case pairingReveal(Data)
    /// The local user confirmed that both devices show the same code.
    case pairingConfirmed
    case pairingRejected
    /// Controller → host: start of the authentication with a stored pairing key.
    case authenticate(nonce: Data)
    /// Host → controller: its nonce and proof of the pairing key.
    case authenticateResponse(nonce: Data, proof: Data)
    /// Controller → host: proof of the pairing key.
    case authenticateProof(Data)
    /// Host → controller: the host does not trust the controller (any more); pair again.
    case pairingRequired

    private enum Kind: String {
        case hello, pairingStart, pairingCommit, pairingNonce, pairingReveal, pairingConfirmed,
             pairingRejected, authenticate, authenticateResponse, authenticateProof, pairingRequired
    }

    private struct KeyAndCommitment: Codable {
        let publicKey: Data
        let commitment: Data
    }

    private struct NonceAndProof: Codable {
        let nonce: Data
        let proof: Data
    }

    func wireData() throws(RemoteProtocolError) -> Data {
        switch self {
        case .hello(let hello): try Wire.encode(type: Kind.hello.rawValue, payload: hello)
        case .pairingStart(let key): try Wire.encode(type: Kind.pairingStart.rawValue, payload: key)
        case .pairingCommit(let key, let commitment):
            try Wire.encode(type: Kind.pairingCommit.rawValue, payload: KeyAndCommitment(publicKey: key, commitment: commitment))
        case .pairingNonce(let nonce): try Wire.encode(type: Kind.pairingNonce.rawValue, payload: nonce)
        case .pairingReveal(let nonce): try Wire.encode(type: Kind.pairingReveal.rawValue, payload: nonce)
        case .pairingConfirmed: try Wire.encode(type: Kind.pairingConfirmed.rawValue)
        case .pairingRejected: try Wire.encode(type: Kind.pairingRejected.rawValue)
        case .authenticate(let nonce): try Wire.encode(type: Kind.authenticate.rawValue, payload: nonce)
        case .authenticateResponse(let nonce, let proof):
            try Wire.encode(type: Kind.authenticateResponse.rawValue, payload: NonceAndProof(nonce: nonce, proof: proof))
        case .authenticateProof(let proof): try Wire.encode(type: Kind.authenticateProof.rawValue, payload: proof)
        case .pairingRequired: try Wire.encode(type: Kind.pairingRequired.rawValue)
        }
    }

    /// `nil` for an unknown type.
    static func fromWire(_ data: Data) throws(RemoteProtocolError) -> HandshakeMessage? {
        guard let kind = Kind(rawValue: try Wire.type(of: data)) else { return nil }
        switch kind {
        case .hello: return .hello(try Wire.payload(Hello.self, from: data))
        case .pairingStart: return .pairingStart(publicKey: try Wire.payload(Data.self, from: data))
        case .pairingCommit:
            let value = try Wire.payload(KeyAndCommitment.self, from: data)
            return .pairingCommit(publicKey: value.publicKey, commitment: value.commitment)
        case .pairingNonce: return .pairingNonce(try Wire.payload(Data.self, from: data))
        case .pairingReveal: return .pairingReveal(try Wire.payload(Data.self, from: data))
        case .pairingConfirmed: return .pairingConfirmed
        case .pairingRejected: return .pairingRejected
        case .authenticate: return .authenticate(nonce: try Wire.payload(Data.self, from: data))
        case .authenticateResponse:
            let value = try Wire.payload(NonceAndProof.self, from: data)
            return .authenticateResponse(nonce: value.nonce, proof: value.proof)
        case .authenticateProof: return .authenticateProof(try Wire.payload(Data.self, from: data))
        case .pairingRequired: return .pairingRequired
        }
    }
}
