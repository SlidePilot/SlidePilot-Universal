import Foundation
import Network
import Observation
import SlidePilotCore
import SlidePilotRemoteProtocol

/// The remote host and pairing state of this instance (REM-02, REM-03, REM-06).
///
/// Every instance advertises itself while remote control is allowed and accepts
/// connections from controllers; only paired devices get past the handshake (ADR 0017).
/// Pairing starts from Settings ▸ Remote on either device and creates trust in both
/// directions (ADR 0015). Which device controls which is picked later in remote mode (#38).
///
/// The protocol and socket I/O run in `RemoteSession` actors; this class only keeps the
/// state the UI shows. Content and commands for verified sessions come with #116.
@MainActor
@Observable
final class RemoteService {
    /// One row of the device list in Settings ▸ Remote.
    struct Device: Identifiable, Hashable {
        enum Status: Hashable {
            /// Found nearby, not paired.
            case available
            /// This device is pairing with it right now.
            case pairing
            /// Paired, not connected.
            case trusted
            /// Paired and connected to this device as its controller.
            case connected
        }

        let id: InstanceID
        let name: String
        let status: Status
    }

    /// A pairing code waiting for the local user's answer.
    struct PairingRequest: Identifiable {
        let id = UUID()
        let deviceName: String
        /// Six digits, as the protocol derives them.
        let code: String
        fileprivate let session: SessionToken
        fileprivate let confirm: @Sendable () async throws -> Void
        fileprivate let reject: @Sendable () async -> Void

        /// "123 456", easier to compare at a glance.
        var formattedCode: String {
            guard code.count == 6 else { return code }
            return "\(code.prefix(3)) \(code.suffix(3))"
        }
    }

    /// Why a pairing did not work, for an alert.
    struct Problem: Identifiable {
        enum Kind {
            case declined, incompatibleVersion(peerNeedsUpdate: Bool), notVerified, unreachable
        }

        let id = UUID()
        let deviceName: String
        let kind: Kind
    }

    fileprivate typealias SessionToken = UUID

    let identity: LocalIdentity
    private let settings: AppSettings
    private let trustStore: any TrustStore

    private(set) var trustedDevices: [TrustedDevice] = []
    private(set) var pairingRequests: [PairingRequest] = []
    var problem: Problem?

    /// Hosts found by the browsers of the visible Settings ▸ Remote panes.
    private var nearbyHosts: [NearbyHost] = []
    /// Controllers verified on this host, by session.
    private var connectedControllers: [SessionToken: PeerIdentity] = [:]
    /// All host sessions, verified or not, by session.
    @ObservationIgnored private var hostSessions: [SessionToken: HostSession] = [:]
    /// Devices this instance is pairing with as controller.
    private var pairingTasks: [InstanceID: Task<Void, Never>] = [:]
    /// The visible Settings ▸ Remote panes. Pairing requests are only accepted while one is
    /// open, so nobody can start pairing with a device whose user is not expecting it.
    private var openPanes = 0
    @ObservationIgnored private var listenerTask: Task<Void, Never>?

    init(settings: AppSettings, identity: LocalIdentity, trustStore: any TrustStore) {
        self.settings = settings
        self.identity = identity
        self.trustStore = trustStore
        trustedDevices = trustStore.devices()
        updateHosting()
    }

    isolated deinit {
        listenerTask?.cancel()
        pairingTasks.values.forEach { $0.cancel() }
    }

    /// Other devices may find this one and control it once paired.
    var allowsRemoteControl: Bool {
        get { settings.allowsRemoteControl }
        set {
            settings.allowsRemoteControl = newValue
            updateHosting()
        }
    }

    /// Nearby, connected and pairing devices, sorted by name.
    var devices: [Device] {
        let trusted = Set(trustedDevices.map(\.instanceID))
        let connected = Dictionary(connectedControllers.values.map { ($0.instanceID, $0.deviceName) }, uniquingKeysWith: { first, _ in first })
        var names = Dictionary(nearbyHosts.map { ($0.instanceID, $0.name) }, uniquingKeysWith: { first, _ in first })
        names.merge(connected) { _, connectedName in connectedName }
        return names.map { id, name in
            let status: Device.Status =
                if connected[id] != nil { .connected }
                else if pairingTasks[id] != nil { .pairing }
                else if trusted.contains(id) { .trusted }
                else { .available }
            return Device(id: id, name: name, status: status)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Settings pane

    /// Browses for nearby devices while a Settings ▸ Remote pane is visible. Runs until the
    /// calling task is cancelled.
    func browse() async {
        openPanes += 1
        defer {
            openPanes -= 1
            if openPanes == 0 {
                nearbyHosts = []
                rejectPendingHostRequests()
            }
        }
        while !Task.isCancelled {
            try? await RemoteNetwork.browse(excluding: identity.instanceID) { @MainActor [weak self] hosts in
                self?.nearbyHosts = hosts
            }
            // Browsing failed (e.g. no network); try again shortly.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Pairs with a nearby device as its controller (REM-02). Both devices show a code.
    func pair(with id: InstanceID) {
        guard pairingTasks[id] == nil, let host = nearbyHosts.first(where: { $0.instanceID == id }) else { return }
        pairingTasks[id] = Task {
            await self.runPairing(with: host)
            self.pairingTasks[id] = nil
        }
    }

    /// Ends the connection of a controller and removes its trust on both devices (REM-03).
    func disconnect(_ id: InstanceID) {
        removeTrust(for: id)
    }

    /// Forgets a trusted device (REM-03). A connected controller is told and disconnected.
    func removeTrust(for id: InstanceID) {
        pairingTasks[id]?.cancel()
        try? trustStore.removeTrust(for: id)
        for (token, peer) in connectedControllers where peer.instanceID == id {
            if let session = hostSessions[token] {
                Task { try? await session.removeTrustAndClose() }
            }
        }
        trustedDevices = trustStore.devices()
    }

    func confirm(_ request: PairingRequest) {
        pairingRequests.removeAll { $0.id == request.id }
        Task { try? await request.confirm() }
    }

    func reject(_ request: PairingRequest) {
        pairingRequests.removeAll { $0.id == request.id }
        Task { await request.reject() }
    }

    // MARK: - Host

    private func updateHosting() {
        if settings.allowsRemoteControl {
            guard listenerTask == nil else { return }
            listenerTask = Task { [weak self, identity] in
                while !Task.isCancelled {
                    try? await RemoteNetwork.listen(as: identity) { @MainActor connection in
                        await self?.serveController(over: connection)
                    }
                    // The listener failed, e.g. while the app was in the background (iPad);
                    // advertise again shortly.
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } else {
            // Cancelling the listener ends every host session with it.
            listenerTask?.cancel()
            listenerTask = nil
        }
    }

    private func serveController(over connection: NetworkConnection<TCP>) async {
        let token = SessionToken()
        let session = HostSession(local: identity, transport: NetworkTransport(connection: connection), trustStore: trustStore)
        hostSessions[token] = session
        defer {
            hostSessions[token] = nil
            connectedControllers[token] = nil
            pairingRequests.removeAll { $0.session == token }
        }

        async let result = Self.run(session)
        var peer: PeerIdentity?
        var hasShownCode = false
        for await event in session.events {
            switch event {
            case .peerIdentified(let identified):
                peer = identified
            case .pairingCode(let code):
                guard openPanes > 0, let peer else {
                    await session.rejectPairingCode()
                    continue
                }
                hasShownCode = true
                pairingRequests.append(PairingRequest(
                    deviceName: peer.deviceName,
                    code: code,
                    session: token,
                    confirm: { try await session.confirmPairingCode() },
                    reject: { await session.rejectPairingCode() }
                ))
            case .paired:
                trustedDevices = trustStore.devices()
            case .verified(let verified):
                connectedControllers[token] = verified
            case .message:
                // Commands of verified controllers are handled with #116 (REM-05).
                break
            case .pairingRequiredByPeer, .trustRemovedByPeer:
                break
            }
        }
        let error = await result
        if hasShownCode, let peer, case .pairingRejectedByPeer? = error as? RemoteProtocolError {
            problem = Problem(deviceName: peer.deviceName, kind: .declined)
        }
    }

    /// While the last pane closes, nobody can answer a code any more.
    private func rejectPendingHostRequests() {
        for request in pairingRequests where hostSessions[request.session] != nil {
            reject(request)
        }
    }

    // MARK: - Controller (pairing only)

    private func runPairing(with host: NearbyHost) async {
        let token = SessionToken()
        let connection = RemoteNetwork.connection(to: host)
        let session = ControllerSession(local: identity, transport: NetworkTransport(connection: connection), trustStore: trustStore)
        defer { pairingRequests.removeAll { $0.session == token } }

        async let result = Self.run(session)
        var deviceName = host.name
        var isPaired = false
        for await event in session.events {
            switch event {
            case .peerIdentified(let peer):
                deviceName = peer.deviceName
            case .pairingRequiredByPeer:
                // The host forgot this device; the user asked to connect, so pair again.
                try? await session.startPairing()
            case .pairingCode(let code):
                pairingRequests.append(PairingRequest(
                    deviceName: deviceName,
                    code: code,
                    session: token,
                    confirm: { try await session.confirmPairingCode() },
                    reject: { await session.rejectPairingCode() }
                ))
            case .paired:
                trustedDevices = trustStore.devices()
            case .verified:
                // Pairing is done; remote mode (#38) connects again when it is used.
                isPaired = true
                await session.close()
            case .message, .trustRemovedByPeer:
                break
            }
        }
        let error = await result
        trustedDevices = trustStore.devices()
        guard !isPaired, !Task.isCancelled, let error else { return }
        if let kind = Self.problemKind(for: error) {
            problem = Problem(deviceName: deviceName, kind: kind)
        }
    }

    private static func problemKind(for error: any Error) -> Problem.Kind? {
        switch error as? RemoteProtocolError {
        case .pairingRejected?, .connectedToSelf?:
            nil
        case .pairingRejectedByPeer?:
            .declined
        case .incompatibleVersion(let mismatch)?:
            .incompatibleVersion(peerNeedsUpdate: mismatch.peerNeedsUpdate)
        case .commitmentMismatch?, .authenticationFailed?:
            .notVerified
        default:
            .unreachable
        }
    }

    /// Runs a session and returns the error that ended it, if any.
    private nonisolated static func run<O, I>(_ session: RemoteSession<O, I>) async -> (any Error)? {
        do {
            try await session.run()
            return nil
        } catch {
            return error
        }
    }
}
