import Foundation
import Network
import Observation
import SlidePilotCore
import SlidePilotRemoteProtocol

/// The remote host and pairing state of this instance (REM-02, REM-03, REM-06).
///
/// Every instance advertises itself while remote control is allowed and accepts
/// connections from controllers; only paired devices get past the handshake (ADR 0017).
/// Pairing starts in remote mode (REM-07, `RemoteControl`) on the controlling device and
/// creates trust in both directions (ADR 0015); it uses the nearby devices and controller
/// sessions of this service.
///
/// Verified controllers get the open presentations and their slides and may control them
/// (REM-04, REM-05); `RemoteHostState` decides what to send and which commands to apply.
/// The protocol and socket I/O run in `RemoteSession` actors; this class keeps the state
/// the UI shows and carries out the host state's actions.
@MainActor
@Observable
final class RemoteService {
    /// A nearby device that remote mode can control.
    struct Device: Identifiable, Hashable {
        enum Status: Hashable {
            /// Not paired.
            case available
            /// Paired.
            case trusted
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

    /// What goes to one controller, in order.
    private enum Delivery {
        case message(HostMessage)
        /// `sequence` tells a request from an equal one queued later.
        case images(SlideImageRequest, sequence: Int)
    }

    let identity: LocalIdentity
    private let settings: AppSettings
    private let trustStore: any TrustStore
    /// The open documents, which verified controllers see and control.
    private let registry: SessionRegistry

    private(set) var trustedDevices: [TrustedDevice] = []
    private(set) var pairingRequests: [PairingRequest] = []
    var problem: Problem?

    /// Hosts found by the browsers of the open remote mode windows.
    private var nearbyHosts: [NearbyHost] = []
    /// Controllers verified on this host, by session.
    private var connectedControllers: [SessionToken: PeerIdentity] = [:]
    /// All host sessions, verified or not, by session.
    @ObservationIgnored private var hostSessions: [SessionToken: HostSession] = [:]
    /// The visible views that show the pairing alerts (`remoteAlerts()`) in the order they
    /// appeared; the last one shows them. Pairing requests are only accepted while there is one, so a code
    /// never waits unseen (REM-02).
    private(set) var alertPresenters: [UUID] = []
    /// Running `browse()` calls; the nearby hosts are kept while there is one.
    @ObservationIgnored private var browsers = 0
    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var stoppingListenerTask: Task<Void, Never>?
    /// What verified controllers were sent and selected (REM-04 to REM-06).
    @ObservationIgnored private var hostState = RemoteHostState<SessionToken>()
    /// The ordered queue of each host session.
    @ObservationIgnored private var deliveries: [SessionToken: AsyncStream<Delivery>.Continuation] = [:]
    /// The newest images each controller needs; older requests still queued are skipped.
    @ObservationIgnored private var latestImages: [SessionToken: Int] = [:]
    @ObservationIgnored private var nextImageSequence = 0
    /// Watches the open presentations for changes the controllers need.
    @ObservationIgnored private var contentTask: Task<Void, Never>?

    init(settings: AppSettings, identity: LocalIdentity, trustStore: any TrustStore, registry: SessionRegistry) {
        self.settings = settings
        self.identity = identity
        self.trustStore = trustStore
        self.registry = registry
        trustedDevices = trustStore.devices()
        updateHosting()
        contentTask = Task { [weak self, registry] in
            let presentations = Observations { registry.sessions.map(\.hostedPresentation) }
            for await presentations in presentations {
                guard let self else { return }
                carryOut(hostState.update(presentations))
            }
        }
    }

    isolated deinit {
        contentTask?.cancel()
        listenerTask?.cancel()
    }

    /// Other devices may find this one and control it once paired.
    var allowsRemoteControl: Bool {
        get { settings.allowsRemoteControl }
        set {
            settings.allowsRemoteControl = newValue
            updateHosting()
        }
    }

    // MARK: - Pairing alerts

    /// A view that shows the pairing alerts appeared; it shows them from now on.
    func alertPresenterAppeared(_ id: UUID) {
        alertPresenters.removeAll { $0 == id }
        alertPresenters.append(id)
    }

    /// A view that showed the pairing alerts went away.
    func alertPresenterWentAway(_ id: UUID) {
        alertPresenters.removeAll { $0 == id }
        // When one view replaces another, the old one may go before the new one appears;
        // only reject the codes if no view showed up by the next turn.
        Task { [weak self] in
            guard let self, alertPresenters.isEmpty else { return }
            rejectPendingHostRequests()
        }
    }

    // MARK: - Browsing

    /// Browses for nearby devices while a remote mode window is visible. Runs until the
    /// calling task is cancelled.
    func browse() async {
        browsers += 1
        defer {
            browsers -= 1
            if browsers == 0 {
                nearbyHosts = []
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

    /// Forgets a trusted device (REM-03). A connected controller is told and disconnected.
    func removeTrust(for id: InstanceID) {
        try? trustStore.removeTrust(for: id)
        for (token, peer) in connectedControllers where peer.instanceID == id {
            // No more content or commands, also for messages already received (REM-06).
            endHosting(token)
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
            let previous = stoppingListenerTask
            listenerTask = Task { [weak self, identity] in
                // Never advertise twice: wait until the previous listener is gone.
                await previous?.value
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
            stoppingListenerTask = listenerTask
            listenerTask = nil
        }
    }

    private func serveController(over connection: NetworkConnection<TCP>) async {
        let token = SessionToken()
        let session = HostSession(local: identity, transport: NetworkTransport(connection: connection), trustStore: trustStore)
        hostSessions[token] = session
        let (queue, queueContinuation) = AsyncStream<Delivery>.makeStream()
        deliveries[token] = queueContinuation
        defer {
            hostSessions[token] = nil
            connectedControllers[token] = nil
            pairingRequests.removeAll { $0.session == token }
            endHosting(token)
            deliveries[token] = nil
            queueContinuation.finish()
        }

        async let result = Self.run(session)
        async let delivered: Void = deliver(queue, over: session, token: token)
        var peer: PeerIdentity?
        var hasShownCode = false
        for await event in session.events {
            switch event {
            case .peerIdentified(let identified):
                peer = identified
            case .pairingCode(let code):
                guard !alertPresenters.isEmpty, let peer else {
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
                // Trust may have been removed while this event waited (REM-03, REM-06).
                guard trustStore.key(for: verified.instanceID) != nil else {
                    await session.close()
                    continue
                }
                connectedControllers[token] = verified
                carryOut(hostState.controllerVerified(token))
            case .message(let message):
                // The session only passes on messages of a verified controller (REM-06),
                // and the host state ignores controllers it was not told are verified.
                carryOut(hostState.receive(message, from: token))
            case .pairingRequiredByPeer, .trustRemovedByPeer:
                break
            }
        }
        // Nothing queued is rendered or sent for a closed connection.
        endHosting(token)
        queueContinuation.finish()
        await delivered
        let error = await result
        if hasShownCode, let peer, case .pairingRejectedByPeer? = error as? RemoteProtocolError {
            problem = Problem(deviceName: peer.deviceName, kind: .declined)
        }
    }

    /// Queues the host state's messages and applies the controllers' commands.
    private func carryOut(_ actions: [HostAction<SessionToken>]) {
        for action in actions {
            switch action {
            case .send(let message, to: let token):
                deliveries[token]?.yield(.message(message))
            case .sendImages(let request, to: let token):
                nextImageSequence += 1
                latestImages[token] = nextImageSequence
                deliveries[token]?.yield(.images(request, sequence: nextImageSequence))
            case .perform(let command, on: let id):
                registry.session(for: id.rawValue)?.perform(command)
            }
        }
    }

    /// Stops content and commands for a controller and hides the pointer it left.
    private func endHosting(_ token: SessionToken) {
        latestImages[token] = nil
        carryOut(hostState.controllerLeft(token))
    }

    /// Sends one controller's queue in order. Images are rendered here, so a status never
    /// overtakes the images queued before it; images that a newer request replaced while
    /// they waited are skipped.
    private func deliver(_ queue: AsyncStream<Delivery>, over session: HostSession, token: SessionToken) async {
        for await delivery in queue {
            switch delivery {
            case .message(let message):
                try? await session.send(message)
            case .images(let request, let sequence):
                guard latestImages[token] == sequence,
                      let presentation = registry.session(for: request.presentationID.rawValue),
                      let images = await RemoteSlideImages.render(
                          request, from: presentation.cache,
                          audience: presentation.audienceRegion, notes: presentation.splitNotesRegion
                      ),
                      latestImages[token] == sequence
                else { continue }
                try? await session.send(.slideImages(images))
            }
        }
    }

    /// Once no view shows the alerts, nobody can answer a code any more.
    private func rejectPendingHostRequests() {
        for request in pairingRequests where hostSessions[request.session] != nil {
            reject(request)
        }
    }

    // MARK: - Controller

    /// Nearby devices this instance can control in remote mode (REM-07), sorted by name.
    /// Never this instance itself.
    var controllableDevices: [Device] {
        let trusted = Set(trustedDevices.map(\.instanceID))
        var seen = Set<InstanceID>()
        return nearbyHosts
            .filter { seen.insert($0.instanceID).inserted }
            .map { Device(id: $0.instanceID, name: $0.name, status: trusted.contains($0.instanceID) ? .trusted : .available) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A new controller session to a nearby device, or `nil` if it is not nearby. The
    /// caller runs it.
    func controllerSession(to id: InstanceID) -> ControllerSession? {
        guard let host = nearbyHosts.first(where: { $0.instanceID == id }) else { return nil }
        let connection = RemoteNetwork.connection(to: host)
        return ControllerSession(local: identity, transport: NetworkTransport(connection: connection), trustStore: trustStore)
    }

    /// Shows a pairing code of a controller session in remote mode; `owner` removes it again.
    func showPairingCode(_ code: String, deviceName: String, session: ControllerSession, owner: UUID) {
        pairingRequests.append(PairingRequest(
            deviceName: deviceName,
            code: code,
            session: owner,
            confirm: { try await session.confirmPairingCode() },
            reject: { await session.rejectPairingCode() }
        ))
    }

    /// Removes the pairing codes `owner` showed, e.g. when its session ended.
    func removePairingCodes(of owner: UUID) {
        pairingRequests.removeAll { $0.session == owner }
    }

    /// Reads the trusted devices again after a controller session paired or lost trust.
    func trustDidChange() {
        trustedDevices = trustStore.devices()
    }

    /// Shows the alert for an error that ended a connection the user started; returns
    /// whether there was one to show.
    @discardableResult
    func reportProblem(_ error: any Error, deviceName: String) -> Bool {
        guard let kind = Self.problemKind(for: error) else { return false }
        problem = Problem(deviceName: deviceName, kind: kind)
        return true
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
