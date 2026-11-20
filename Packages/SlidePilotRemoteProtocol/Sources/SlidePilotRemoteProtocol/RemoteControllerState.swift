import Foundation

/// A command the controller user gives for the selected presentation (REM-05, REM-07).
public enum ControllerCommand: Sendable, Equatable {
    case nextSlide
    case previousSlide
    case setCurtain(RemoteCurtain)
    case pointerMoved(PointerPosition)
    case pointerFinished
}

/// What a controller knows about the host it controls and what it sends next (REM-04,
/// REM-05, REM-07). The controller side of `RemoteHostState`: no I/O, the app feeds it the
/// host's messages and the user's actions and sends the returned messages in order.
///
/// Flow (see `RemoteHostState`): after verification the host sends its presentations; the
/// controller selects one with its image size; the host answers with status and images and
/// sends them again on every change.
public struct RemoteControllerState: Sendable, Equatable {
    /// The host's open presentations; empty until the host sent them.
    public private(set) var presentations: [PresentationSummary] = []
    /// Whether the host sent its presentations since the connection was verified.
    public private(set) var hasPresentations = false
    /// The presentation this controller shows and controls.
    public private(set) var selection: PresentationID?
    /// Meta and notes of the selection; `nil` until the host sent them.
    public private(set) var status: PresentationStatus?
    /// The newest images of the selection; `nil` until the host sent them.
    public private(set) var images: SlideImages?
    /// The title of the selection the host closed, until the user picks another one.
    public private(set) var closedTitle: String?

    /// The selection to pick again when the host lists it after a reconnect.
    private var preferredSelection: PresentationID?
    private var imageSize = PixelSize(width: 1, height: 1)

    public init() {}

    /// The selected presentation's entry in the host's list.
    public var selectedPresentation: PresentationSummary? {
        presentations.first { $0.id == selection }
    }

    /// The connection was verified (again). Everything the host sent before is outdated;
    /// the selection is picked again once the host lists it.
    public mutating func connectionVerified() {
        preferredSelection = selection ?? preferredSelection
        presentations = []
        hasPresentations = false
        selection = nil
        status = nil
        images = nil
    }

    /// A message of the host. Returns what to send in answer.
    public mutating func receive(_ message: HostMessage) -> [ControllerMessage] {
        switch message {
        case .presentations(let list):
            let isFirstList = !hasPresentations
            if let selection, !list.contains(where: { $0.id == selection }) {
                // The host also sends `presentationClosed`; this keeps the state right
                // without it.
                closeSelection()
            }
            presentations = list
            hasPresentations = true
            guard selection == nil, isFirstList else { return [] }
            // Pick the previous presentation again after a reconnect, or the only one.
            if let preferred = preferredSelection, list.contains(where: { $0.id == preferred }) {
                return select(preferred)
            }
            if list.count == 1, closedTitle == nil {
                return select(list[0].id)
            }
            return []
        case .status(let newStatus):
            guard newStatus.presentationID == selection else { return [] }
            status = newStatus
        case .slideImages(let newImages):
            guard newImages.presentationID == selection else { return [] }
            images = newImages
        case .presentationClosed(let id):
            guard id == selection else { return [] }
            closeSelection()
        case .trustRemoved:
            // The session deletes the key and ends the connection.
            break
        }
        return []
    }

    /// The user picked a presentation of the host.
    public mutating func select(_ id: PresentationID) -> [ControllerMessage] {
        guard presentations.contains(where: { $0.id == id }) else { return [] }
        selection = id
        preferredSelection = id
        closedTitle = nil
        status = nil
        images = nil
        return [.selectPresentation(id, imageSize: imageSize)]
    }

    /// The user went back to the list of presentations. The host keeps sending updates of
    /// the old selection; they are ignored.
    public mutating func deselect() -> [ControllerMessage] {
        let pointer: [ControllerMessage] = selection == nil ? [] : [.pointerFinished]
        selection = nil
        preferredSelection = nil
        status = nil
        images = nil
        return pointer
    }

    /// The controller's slide area changed. Returns `setImageSize` only when it changed and
    /// a presentation is selected; the selection sends the size itself.
    public mutating func setImageSize(_ size: PixelSize) -> [ControllerMessage] {
        guard size != imageSize else { return [] }
        imageSize = size
        return selection == nil ? [] : [.setImageSize(size)]
    }

    /// The image size to ask for, for a slide area of `width` × `height` pixels: rounded up
    /// to multiples of 128 px, so resizing a window does not make the host render the
    /// images again for every pixel.
    public static func requestedImageSize(width: Double, height: Double) -> PixelSize {
        func rounded(_ value: Double) -> Int {
            guard value.isFinite, value > 0 else { return 128 }
            return Int((min(value, 8192) / 128).rounded(.up)) * 128
        }
        return PixelSize(width: rounded(width), height: rounded(height))
    }

    /// A command for the selected presentation; nothing without a selection.
    public func command(_ command: ControllerCommand) -> [ControllerMessage] {
        guard selection != nil else { return [] }
        return switch command {
        case .nextSlide: [.nextSlide]
        case .previousSlide: [.previousSlide]
        case .setCurtain(let curtain): [.setCurtain(curtain)]
        case .pointerMoved(let position): [.pointerMoved(position)]
        case .pointerFinished: [.pointerFinished]
        }
    }

    /// The curtain a tap on the curtain button sets: black while none is shown, otherwise
    /// none (REM-07; the menu offers black and white).
    public var curtainToggleTarget: RemoteCurtain {
        (status?.curtain ?? RemoteCurtain.none) == RemoteCurtain.none ? .black : .none
    }

    /// The fraction of the presentation shown so far: the slide number over the slide
    /// count, so the last slide is 1.
    public var progress: Double? {
        guard let status, status.slideCount > 0 else { return nil }
        return Double(min(max(status.slideNumber, 0), status.slideCount)) / Double(status.slideCount)
    }

    private mutating func closeSelection() {
        closedTitle = selectedPresentation?.title ?? closedTitle
        selection = nil
        preferredSelection = nil
        status = nil
        images = nil
    }
}
