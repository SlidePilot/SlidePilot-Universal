import Foundation
import Network
import SlidePilotRemoteProtocol

/// Network framework glue for the remote (ADR 0017): Bonjour advertising and browsing and
/// TCP connections. The protocol itself runs in `RemoteSession`; this file only moves bytes.
nonisolated enum RemoteNetwork {
    /// Gives up on a peer that does not answer, instead of waiting forever.
    private static let connectionTimeoutSeconds: UInt32 = 10

    /// TCP with keepalive, so a peer that left the network without closing (sleep, Wi-Fi
    /// off) ends its session within about half a minute instead of never.
    private static func tcp() -> TCP {
        TCP().keepalive(idleTimeInSeconds: 15, count: 3, intervalInSeconds: 5)
    }

    /// Advertises this instance as a host and hands every incoming connection to `handler`.
    /// Runs until the calling task is cancelled or the listener fails. A connection is
    /// closed when its handler returns.
    static func listen(
        as identity: LocalIdentity,
        handler: @escaping @Sendable (NetworkConnection<TCP>) async -> Void
    ) async throws {
        let txtRecord = NWTXTRecord(RemoteDiscovery.txtRecord(for: identity.instanceID))
        let listener = try NetworkListener(
            for: .bonjour(name: identity.deviceName, type: RemoteDiscovery.bonjourServiceType, txtRecord: txtRecord)
        ) {
            tcp()
        }
        try await listener.run { connection in
            await handler(connection)
        }
    }

    /// Reports the other SlidePilot instances nearby whenever the list changes, until the
    /// calling task is cancelled or browsing fails. Never lists this instance itself.
    static func browse(
        excluding localInstanceID: InstanceID,
        onChange: @escaping @Sendable ([NearbyHost]) async -> Void
    ) async throws {
        let browser = NetworkBrowser(for: .bonjour(RemoteDiscovery.bonjourServiceType, includeTxtRecord: true))
        try await browser.run { endpoints in
            let hosts = endpoints.compactMap { NearbyHost(endpoint: $0, localInstanceID: localInstanceID) }
            await onChange(hosts)
        }
    }

    /// A new connection to a host; it starts when the session first sends.
    static func connection(to host: NearbyHost) -> NetworkConnection<TCP> {
        NetworkConnection(to: host.endpoint) {
            tcp().connectionTimeout(connectionTimeoutSeconds)
        }
    }
}

/// Another SlidePilot instance found by Bonjour.
nonisolated struct NearbyHost: Sendable, Equatable {
    let instanceID: InstanceID
    /// The Bonjour service name, which is the device name the host advertises.
    let name: String
    let endpoint: Bonjour.Endpoint

    init?(endpoint: Bonjour.Endpoint, localInstanceID: InstanceID) {
        let txtRecord = endpoint.txtRecord.dictionary
        guard RemoteDiscovery.shouldList(txtRecord: txtRecord, localInstanceID: localInstanceID),
              let value = txtRecord[RemoteDiscovery.TXTKey.instanceID],
              let instanceID = InstanceID(string: value) else { return nil }
        self.instanceID = instanceID
        name = endpoint.name
        self.endpoint = endpoint
    }
}

/// A TCP connection as the byte stream of a `RemoteSession`.
nonisolated struct NetworkTransport: RemoteTransport {
    /// Large enough for a slide image arriving in few reads, small enough to stay cheap.
    private static let maximumReadLength = 256 * 1024

    let connection: NetworkConnection<TCP>

    func send(_ bytes: Data) async throws {
        try await connection.send(bytes)
    }

    func receive() async throws -> Data? {
        let (content, metadata) = try await connection.receive(atLeast: 1, atMost: Self.maximumReadLength)
        if content.isEmpty, metadata.endOfStream { return nil }
        return content
    }
}
