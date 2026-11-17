/// Protocol version negotiation (ADR 0017).
public enum ProtocolVersion {
    /// The newest version this build speaks.
    public static let current = 1
    /// The oldest version this build still speaks.
    public static let minimumSupported = 1

    public static var supported: ClosedRange<Int> { minimumSupported...current }

    /// The highest version both ranges contain, or `nil` if they do not overlap.
    public static func negotiate(local: ClosedRange<Int>, peer: ClosedRange<Int>) -> Int? {
        let version = min(local.upperBound, peer.upperBound)
        return version >= max(local.lowerBound, peer.lowerBound) ? version : nil
    }
}

/// Two instances whose protocol versions do not overlap.
public struct VersionMismatch: Sendable, Equatable {
    public let local: ClosedRange<Int>
    public let peer: ClosedRange<Int>

    /// `true` if the peer has to be updated, `false` if this instance has to be updated.
    public var peerNeedsUpdate: Bool { peer.upperBound < local.lowerBound }
}
