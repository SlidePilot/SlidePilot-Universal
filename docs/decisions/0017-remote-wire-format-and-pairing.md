# 0017 – Remote wire format, versioning, pairing and encryption

- Status: Accepted
- Date: 2026-11-17
- Refines: [0006](0006-remote-protocol.md), [0015](0015-iphone-and-remote-mode.md)

## Context
ADR 0006 chose the Network framework, Bonjour and an encrypted connection keyed from pairing; ADR 0015 made the roles symmetric (every instance can host and control). The details were open: how messages are framed and encoded, how versions are negotiated, how two devices pair, and how the connection is encrypted. The old app used a 4-digit code shown on the remote and confirmed only on the Mac, and accepted commands from unverified devices (DEF-04).

Network framework TLS with pre-shared keys is only reachable through sparsely documented TLS 1.2 PSK cipher suites. Encryption on the application layer with CryptoKit is fully testable in a package without sockets.

## Decision
**Transport** (implemented by the app, issue #37): TCP over the Network framework, Bonjour service type `_slidepilot._tcp`. Every instance advertises itself as host and can browse as controller. The TXT record carries the instance ID and the protocol version.

**Framing and encoding**: each frame is a 4-byte big-endian length followed by the payload (at most 16 MiB). Messages are Codable and encoded as JSON with a `type` discriminator. Images travel as JPEG or HEIC data (Base64 in JSON). Unknown message types are skipped, so a newer minor revision does not break an older peer.

**Versioning**: both sides send `hello` first, in clear text, with their supported protocol version range, instance ID, device name and role. The highest version both support is used; if the ranges do not overlap, both sides fail with `incompatibleVersion`, which tells the app which side needs an update. The shape of `hello` never changes.

**Pairing** (numeric comparison with a commitment, as in Bluetooth Secure Simple Pairing):
1. Controller → host: ephemeral X25519 public key.
2. Host → controller: its ephemeral public key and a commitment `SHA256(hostNonce ‖ hostKey ‖ controllerKey)`.
3. Controller → host: its random nonce.
4. Host → controller: its nonce; the controller checks the commitment.
5. Both show a 6-digit code derived from a hash of both keys, both nonces, both instance IDs and both `hello` messages. The user confirms it on **both** devices. The commitment means a man in the middle must fix its values before it learns the other nonce, so it matches the codes only with a chance of 1 in 10⁶.
6. After both confirmations, both derive a 256-bit pairing key with HKDF-SHA256 from the X25519 shared secret, salted with the transcript hash. The app stores it in the Keychain per device pair (#37) and reconnects with it later.

**Encryption**: every connection runs an authentication step with the pairing key. Both sides send a random nonce; HKDF derives one ChaCha20-Poly1305 key per direction and a confirmation key. Each side proves the key with an HMAC over both nonces, both instance IDs and both `hello` messages, so a relay that changes a name, role or version range makes the proofs fail. Nonces are message counters, so replayed, reordered or dropped frames fail. The connection state is not copyable, so a copy can never reuse a nonce. If the host does not know the controller any more, it answers `pairingRequired`. That answer is not authenticated, so the controller keeps its key and pairs again only when the user asks. A verified host removes trust with the encrypted `trustRemoved` message before it disconnects (REM-03).

**Verification (REM-06)**: the connection state machine in `SlidePilotRemoteProtocol` accepts only handshake messages until the peer is verified; commands and content exist only as encrypted frames after verification.

**No self-connection**: every instance has a random instance ID. The controller hides its own ID from the discovery list, and both sides reject a `hello` with their own ID.

## Consequences
- No new dependencies (CryptoKit and the Network framework are part of the OS).
- Pairing, key derivation, framing, versioning and the state machine are covered by package tests; the app only moves frames between sockets and the state machine.
- The pairing key is a secret: the app must store it in the Keychain, never in user defaults or the companion file.
- A future TLS-based transport would need a new protocol version.
