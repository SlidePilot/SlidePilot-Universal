import CryptoKit
import Foundation

/// The long-term secret of one device pair. The app stores it in the Keychain, never in
/// user defaults or the companion file (ADR 0017).
public struct PairingKey: Sendable, CustomStringConvertible {
    public static let byteCount = 32

    /// The key bytes, for the Keychain.
    public let rawRepresentation: Data

    public init?(rawRepresentation: Data) {
        guard rawRepresentation.count == Self.byteCount else { return nil }
        self.rawRepresentation = rawRepresentation
    }

    /// Keeps the key out of logs.
    public var description: String { "PairingKey(redacted)" }

    var symmetricKey: SymmetricKey { SymmetricKey(data: rawRepresentation) }
}

/// Primitives of the pairing and authentication steps in ADR 0017.
enum RemoteCrypto {
    static let nonceByteCount = 32
    static let publicKeyByteCount = 32

    static func randomBytes(_ count: Int = nonceByteCount) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    static func sha256(_ parts: Data...) -> Data {
        var hash = SHA256()
        for part in parts { hash.update(data: part) }
        return Data(hash.finalize())
    }

    /// The host's commitment to its nonce, sent before it learns the controller's nonce.
    static func commitment(hostNonce: Data, hostKey: Data, controllerKey: Data) -> Data {
        sha256(Data("SlidePilot commitment v1".utf8), hostNonce, hostKey, controllerKey)
    }

    /// Everything both sides exchanged during pairing, in a fixed order.
    struct PairingTranscript {
        let controllerKey: Data
        let hostKey: Data
        let controllerNonce: Data
        let hostNonce: Data
        let controllerID: InstanceID
        let hostID: InstanceID
        /// Hash of both `hello` payloads.
        let helloDigest: Data

        var bytes: Data {
            controllerKey + hostKey + controllerNonce + hostNonce + controllerID.transcriptBytes + hostID.transcriptBytes + helloDigest
        }

        /// The 6-digit code both users compare.
        var code: String {
            let hash = sha256(Data("SlidePilot pairing code v1".utf8), bytes)
            let value = hash.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let digits = String(value % 1_000_000)
            return String(repeating: "0", count: 6 - digits.count) + digits
        }

        func pairingKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peerKey: Data) throws(RemoteProtocolError) -> PairingKey {
            do {
                let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey)
                let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
                let key = shared.hkdfDerivedSymmetricKey(
                    using: SHA256.self,
                    salt: sha256(bytes),
                    sharedInfo: Data("SlidePilot pairing key v1".utf8),
                    outputByteCount: PairingKey.byteCount
                )
                guard let pairingKey = PairingKey(rawRepresentation: key.withUnsafeBytes { Data($0) }) else {
                    throw RemoteProtocolError.invalidMessage
                }
                return pairingKey
            } catch {
                throw .invalidMessage
            }
        }
    }

    /// Per-connection keys derived from the pairing key and both nonces.
    struct SessionKeys: Sendable {
        let controllerToHost: Data
        let hostToController: Data
        private let confirmation: Data
        private let transcript: Data

        init(pairingKey: PairingKey, controllerNonce: Data, hostNonce: Data, controllerID: InstanceID, hostID: InstanceID, helloDigest: Data) {
            // The hello digest in the salt makes a relayed, modified hello fail the proofs.
            let salt = controllerNonce + hostNonce + helloDigest
            func derive(_ label: String) -> Data {
                HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: pairingKey.symmetricKey,
                    salt: salt,
                    info: Data("SlidePilot session v1 \(label)".utf8),
                    outputByteCount: 32
                ).withUnsafeBytes { Data($0) }
            }
            controllerToHost = derive("controller-to-host")
            hostToController = derive("host-to-controller")
            confirmation = derive("confirmation")
            transcript = salt + controllerID.transcriptBytes + hostID.transcriptBytes
        }

        /// Proves to the peer that `role` knows the pairing key.
        func proof(by role: RemoteRole) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: Data(role.rawValue.utf8) + transcript, using: SymmetricKey(data: confirmation)))
        }

        func isValid(proof: Data, by role: RemoteRole) -> Bool {
            HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Data(role.rawValue.utf8) + transcript, using: SymmetricKey(data: confirmation))
        }

        func channel(for role: RemoteRole) -> SecureChannel {
            role == .controller
                ? SecureChannel(sendKey: controllerToHost, receiveKey: hostToController)
                : SecureChannel(sendKey: hostToController, receiveKey: controllerToHost)
        }
    }
}

/// ChaCha20-Poly1305 with one key per direction. Nonces are message counters and are not
/// sent, so a replayed, reordered or dropped frame fails to open.
struct SecureChannel: Sendable {
    static let tagByteCount = 16

    private let sendKey: Data
    private let receiveKey: Data
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    init(sendKey: Data, receiveKey: Data) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    mutating func seal(_ plaintext: Data) throws(RemoteProtocolError) -> Data {
        do {
            let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: sendKey), nonce: Self.nonce(sendCounter))
            sendCounter += 1
            return box.ciphertext + box.tag
        } catch {
            throw .invalidMessage
        }
    }

    mutating func open(_ data: Data) throws(RemoteProtocolError) -> Data {
        guard data.count >= Self.tagByteCount else { throw .authenticationFailed }
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: Self.nonce(receiveCounter),
                ciphertext: data.dropLast(Self.tagByteCount),
                tag: data.suffix(Self.tagByteCount)
            )
            let plaintext = try ChaChaPoly.open(box, using: SymmetricKey(data: receiveKey))
            receiveCounter += 1
            return plaintext
        } catch {
            throw .authenticationFailed
        }
    }

    private static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        // 12 bytes are always a valid ChaChaPoly nonce.
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}
