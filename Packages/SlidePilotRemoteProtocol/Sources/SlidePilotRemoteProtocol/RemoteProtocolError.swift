/// Why a connection ended. Every error is final: the app closes the connection.
public enum RemoteProtocolError: Error, Sendable, Equatable {
    /// The peer speaks no protocol version this instance speaks.
    case incompatibleVersion(VersionMismatch)
    /// The peer is this instance (same instance ID).
    case connectedToSelf
    /// Both sides claim the same role.
    case roleConflict
    /// A frame is longer than `FrameDecoder.maximumFrameLength`.
    case frameTooLarge(Int)
    /// A frame could not be decoded or has invalid values.
    case invalidMessage
    /// A valid message arrived in a state that does not expect it.
    case unexpectedMessage
    /// The host's pairing values do not match its commitment (likely a man in the middle).
    case commitmentMismatch
    /// The peer rejected the pairing code.
    case pairingRejectedByPeer
    /// The local user rejected the pairing code.
    case pairingRejected
    /// The peer does not prove the pairing key, or an encrypted frame failed to open.
    case authenticationFailed
    /// Content or commands before the peer is verified (REM-06).
    case notVerified
    /// The connection already failed.
    case connectionClosed
}
