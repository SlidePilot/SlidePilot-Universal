import CoreGraphics
import Foundation
import ImageIO
import Observation
import SlidePilotRemoteProtocol
import SwiftUI

/// Remote mode of one window (REM-07, ADR 0015): connects to a trusted nearby device as its
/// controller, shows one of its presentations and sends the user's commands.
///
/// The protocol runs in a `ControllerSession` actor; `RemoteControllerState` decides what
/// to send. While the window is open, a lost connection is retried, so the controller
/// reconnects when both apps are active again (REM-02).
@MainActor
@Observable
final class RemoteControl {
    enum Connection: Equatable {
        /// Not connected to a device; the device list is shown.
        case idle
        /// Connecting for the first time (and pairing, if the host asks for it).
        case connecting
        case connected
        /// The connection was lost or the device is not nearby; trying again.
        case reconnecting
    }

    /// Why remote mode went back to the device list on its own.
    enum Ending: Identifiable {
        /// The device removed this one from its trusted devices (REM-03).
        case trustRemoved(deviceName: String)
        /// The device does not know this one any more; it has to be paired again.
        case pairingRequired(deviceName: String)

        var id: String {
            switch self {
            case .trustRemoved(let name): "trustRemoved-\(name)"
            case .pairingRequired(let name): "pairingRequired-\(name)"
            }
        }
    }

    /// The decoded images of one slide.
    struct Slides {
        let slideIndex: Int
        let current: CGImage?
        /// `nil` on the last slide, where the next slide shows black.
        let next: CGImage?
        /// The notes half of the page in split notes mode.
        let notes: CGImage?
    }

    private(set) var deviceID: InstanceID?
    private(set) var deviceName = ""
    private(set) var connection = Connection.idle
    private(set) var state = RemoteControllerState()
    private(set) var slides: Slides?
    /// The notes text of the current slide.
    private(set) var notes: AttributedString?
    var ending: Ending?

    @ObservationIgnored private let remote: RemoteService
    /// Changes with every `connect` and `disconnect`; the window restarts `keepConnected()`
    /// for it, so the connection lives exactly as long as the window and its device choice.
    private(set) var connectionID = UUID()
    @ObservationIgnored private var decodeTask: Task<Void, Never>?
    /// The ordered outgoing messages of the running session.
    @ObservationIgnored private var outgoing: AsyncStream<ControllerMessage>.Continuation?
    @ObservationIgnored private var outgoingOwner: UUID?
    @ObservationIgnored private var gestures = RemoteGestureInterpreter()
    /// Tells the newest decoded images from older ones that finish later.
    @ObservationIgnored private var imageSequence = 0

    init(remote: RemoteService) {
        self.remote = remote
    }

    isolated deinit {
        decodeTask?.cancel()
        outgoing?.finish()
    }

    // MARK: - Navigation

    /// The screens of the window's navigation stack.
    enum Route: Hashable {
        case presentations
        case slides
    }

    var route: [Route] {
        guard deviceID != nil else { return [] }
        return state.selection == nil ? [.presentations] : [.presentations, .slides]
    }

    /// The navigation stack went back (back button, swipe or Escape).
    func navigate(to newRoute: [Route]) {
        if newRoute.count < 2, state.selection != nil {
            send(state.deselect())
            slides = nil
            notes = nil
        }
        if newRoute.isEmpty, deviceID != nil {
            disconnect()
        }
    }

    // MARK: - Connection

    /// Connects to a trusted nearby device; pairs first if the device asks for it.
    func connect(to device: RemoteService.Device) {
        disconnect()
        deviceID = device.id
        deviceName = device.name
        connection = .connecting
        connectionID = UUID()
    }

    /// Ends remote mode and goes back to the device list.
    func disconnect() {
        connectionID = UUID()
        decodeTask?.cancel()
        outgoing?.finish()
        outgoing = nil
        outgoingOwner = nil
        deviceID = nil
        connection = .idle
        state = RemoteControllerState()
        slides = nil
        notes = nil
        gestures = RemoteGestureInterpreter()
    }

    private enum SessionEnd {
        /// Try again shortly.
        case retry
        /// Back to the device list.
        case stop
    }

    /// Connects to the chosen device and keeps the connection until the calling task is
    /// cancelled. The window runs it with `.task(id: connectionID)`, so closing the window,
    /// `connect` and `disconnect` end it.
    func keepConnected() async {
        guard let id = deviceID else { return }
        var isFirstAttempt = true
        while !Task.isCancelled {
            if let session = remote.controllerSession(to: id) {
                let end = await run(session, isFirstAttempt: isFirstAttempt)
                if end == .stop || Task.isCancelled {
                    if !Task.isCancelled { disconnect() }
                    return
                }
                isFirstAttempt = false
            }
            if !Task.isCancelled {
                connection = isFirstAttempt ? .connecting : .reconnecting
            }
            // The device is not nearby or the connection was lost; it may come back, e.g.
            // when its app becomes active again.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func run(_ session: ControllerSession, isFirstAttempt: Bool) async -> SessionEnd {
        let owner = UUID()
        let (messages, continuation) = AsyncStream<ControllerMessage>.makeStream()
        defer {
            continuation.finish()
            remote.removePairingCodes(of: owner)
        }

        async let result = Self.run(session)
        // Sends in the order the messages were made; the session encrypts them in that order.
        async let sent: Void = {
            for await message in messages {
                try? await session.send(message)
            }
        }()

        var end = SessionEnd.retry
        var wasVerified = false
        var hasShownCode = false
        for await event in session.events {
            // Events still buffered when the user went back or picked another device
            // belong to the old connection.
            guard !Task.isCancelled else { break }
            switch event {
            case .peerIdentified(let peer):
                deviceName = peer.deviceName
            case .pairingRequiredByPeer:
                if isFirstAttempt {
                    // The user asked to connect, so pair again, as in Settings ▸ Remote.
                    try? await session.startPairing()
                    guard !Task.isCancelled else { break }
                } else {
                    ending = .pairingRequired(deviceName: deviceName)
                    end = .stop
                    await session.close()
                }
            case .pairingCode(let code):
                hasShownCode = true
                remote.showPairingCode(code, deviceName: deviceName, session: session, owner: owner)
            case .paired:
                remote.trustDidChange()
            case .verified:
                wasVerified = true
                outgoing = continuation
                outgoingOwner = owner
                state.connectionVerified()
                slides = nil
                notes = nil
                connection = .connected
            case .message(let message):
                receive(message)
            case .trustRemovedByPeer:
                remote.trustDidChange()
                ending = .trustRemoved(deviceName: deviceName)
                end = .stop
            }
        }
        if outgoingOwner == owner {
            outgoing = nil
            outgoingOwner = nil
        }
        continuation.finish()
        await sent
        let error = await result
        guard end == .retry, !wasVerified, !Task.isCancelled, let error else { return end }
        // The connection the user asked for never got verified (declined, incompatible,
        // unreachable): tell the user and go back. Later attempts keep trying.
        guard isFirstAttempt || hasShownCode else { return .retry }
        remote.reportProblem(error, deviceName: deviceName)
        return .stop
    }

    /// Runs a session and returns the error that ended it, if any.
    private nonisolated static func run(_ session: ControllerSession) async -> (any Error)? {
        do {
            try await session.run()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Host content

    private func receive(_ message: HostMessage) {
        let previousStatus = state.status
        send(state.receive(message))
        switch message {
        case .slideImages(let images) where state.images == images:
            decode(images)
        case .presentationClosed, .presentations:
            if state.selection == nil {
                slides = nil
                notes = nil
            }
        default:
            break
        }
        if state.status?.notesRTF != previousStatus?.notesRTF || state.status == nil {
            notes = state.status?.notesRTF.flatMap(RemoteNotesText.attributedString(from:))
        }
    }

    private func decode(_ images: SlideImages) {
        imageSequence += 1
        let sequence = imageSequence
        decodeTask?.cancel()
        decodeTask = Task {
            let decoded = await Self.decode(images)
            // A newer image or another selection replaced these while they were decoded.
            guard !Task.isCancelled, let decoded, sequence == imageSequence,
                  state.images?.presentationID == images.presentationID else { return }
            slides = decoded
        }
    }

    @concurrent
    private nonisolated static func decode(_ images: SlideImages) async -> Slides? {
        let current = cgImage(images.current)
        guard !Task.isCancelled else { return nil }
        let next = images.next.flatMap(cgImage)
        guard !Task.isCancelled else { return nil }
        return Slides(slideIndex: images.slideIndex, current: current, next: next, notes: images.notes.flatMap(cgImage))
    }

    private nonisolated static func cgImage(_ image: EncodedImage) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(image.data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Commands

    func select(_ id: PresentationID) {
        slides = nil
        notes = nil
        send(state.select(id))
    }

    func perform(_ command: ControllerCommand) {
        send(state.command(command))
    }

    /// The slide area is `size` points large at `scale` pixels per point.
    func setSlideAreaSize(_ size: CGSize, scale: CGFloat) {
        let pixels = RemoteControllerState.requestedImageSize(width: size.width * scale, height: size.height * scale)
        send(state.setImageSize(pixels))
    }

    /// A finger (or the mouse) moved on the current slide.
    func touchMoved(start: CGPoint, location: CGPoint, time: Date, slideSize: CGSize) {
        let position = PointerPosition(
            x: slideSize.width > 0 ? location.x / slideSize.width : 0,
            y: slideSize.height > 0 ? location.y / slideSize.height : 0
        )
        let commands = gestures.moved(start: .init(start), location: .init(location), time: time.timeIntervalSinceReferenceDate, slidePosition: position)
        commands.forEach(perform)
    }

    func touchEnded(start: CGPoint, location: CGPoint, time: Date) {
        gestures.ended(start: .init(start), location: .init(location), time: time.timeIntervalSinceReferenceDate).forEach(perform)
    }

    /// A pinch started; the touch is no swipe or pointer move.
    func cancelTouch() {
        gestures.cancel().forEach(perform)
    }

    var isMovingPointer: Bool { gestures.isMovingPointer }

    private func send(_ messages: [ControllerMessage]) {
        for message in messages {
            outgoing?.yield(message)
        }
    }
}

private extension RemoteGestureInterpreter.Point {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }
}
