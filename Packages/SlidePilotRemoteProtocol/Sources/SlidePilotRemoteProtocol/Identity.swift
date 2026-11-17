import Foundation

/// A random, stable ID of one SlidePilot installation. It tells a device apart from itself
/// and keys the trust store (ADR 0017).
public struct InstanceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        rawValue = uuid
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }

    /// Canonical bytes for transcripts and proofs.
    var transcriptBytes: Data { Data(rawValue.uuidString.utf8) }
}

/// Which side of a connection an instance plays. Every instance can play both (ADR 0015),
/// but each connection has exactly one host and one controller.
public enum RemoteRole: String, Codable, Sendable {
    /// Offers its open presentations and is controlled.
    case host
    /// Controls a presentation of another instance.
    case controller

    var opposite: RemoteRole { self == .host ? .controller : .host }
}

/// The local instance as it introduces itself to a peer.
public struct LocalIdentity: Sendable, Equatable {
    public var instanceID: InstanceID
    /// User-visible device name, e.g. the name set in the system settings.
    public var deviceName: String

    public init(instanceID: InstanceID, deviceName: String) {
        self.instanceID = instanceID
        self.deviceName = deviceName
    }
}

/// The peer of a connection, known after its `hello`.
public struct PeerIdentity: Sendable, Equatable, Hashable {
    public let instanceID: InstanceID
    public let deviceName: String
}

/// Bonjour advertisement and discovery rules (ADR 0017). The app owns the sockets.
public enum RemoteDiscovery {
    /// Must also be listed in `NSBonjourServices`.
    public static let bonjourServiceType = "_slidepilot._tcp"

    public enum TXTKey {
        public static let instanceID = "id"
        public static let protocolVersion = "v"
    }

    /// The TXT record a host advertises.
    public static func txtRecord(for instanceID: InstanceID) -> [String: String] {
        [
            TXTKey.instanceID: instanceID.description,
            TXTKey.protocolVersion: String(ProtocolVersion.current),
        ]
    }

    /// Whether a discovered service belongs in the device list: never the local instance
    /// itself, and never a service without a valid instance ID.
    public static func shouldList(txtRecord: [String: String], localInstanceID: InstanceID) -> Bool {
        guard let value = txtRecord[TXTKey.instanceID], let id = InstanceID(string: value) else {
            return false
        }
        return id != localInstanceID
    }
}
