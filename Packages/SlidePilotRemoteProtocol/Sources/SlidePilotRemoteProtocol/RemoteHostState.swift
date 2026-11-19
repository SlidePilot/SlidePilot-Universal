import Foundation

/// What the host shows of one open presentation, as far as controllers need it (REM-04).
public struct HostedPresentation: Sendable, Equatable {
    public var id: PresentationID
    /// The document's display name.
    public var title: String
    /// Zero-based index of the current slide.
    public var slideIndex: Int
    public var slideCount: Int
    public var curtain: RemoteCurtain
    /// RTF notes of the current slide; `nil` if it has none.
    public var notesRTF: Data?
    /// Changes whenever the slide images change without a page change, e.g. after a reload
    /// (DOC-08). Split notes (#28) bump it when the notes position changes.
    public var contentVersion: Int

    public init(id: PresentationID, title: String, slideIndex: Int, slideCount: Int, curtain: RemoteCurtain, notesRTF: Data?, contentVersion: Int) {
        self.id = id
        self.title = title
        self.slideIndex = slideIndex
        self.slideCount = slideCount
        self.curtain = curtain
        self.notesRTF = notesRTF
        self.contentVersion = contentVersion
    }

    var summary: PresentationSummary {
        PresentationSummary(id: id, title: title, slideCount: slideCount)
    }

    var status: PresentationStatus {
        PresentationStatus(presentationID: id, slideIndex: slideIndex, slideCount: slideCount, curtain: curtain, notesRTF: notesRTF)
    }
}

/// The slide images one controller needs. The host renders them and sends `SlideImages`.
public struct SlideImageRequest: Sendable, Equatable {
    public let presentationID: PresentationID
    public let slideIndex: Int
    /// The following slide, or `nil` on the last slide (the controller shows black).
    public let nextSlideIndex: Int?
    /// At least this size; the controller scales the images down itself (PRE-02).
    public let size: PixelSize
    public let contentVersion: Int
}

/// A command of a controller for the presentation it selected (REM-05).
public enum HostCommand: Sendable, Equatable {
    case nextSlide
    case previousSlide
    case setCurtain(RemoteCurtain)
    case pointerMoved(PointerPosition)
    case pointerFinished
}

/// What the host does next, in this order.
public enum HostAction<Controller: Hashable & Sendable>: Sendable, Equatable {
    /// Sends a message to a verified controller.
    case send(HostMessage, to: Controller)
    /// Renders slide images and sends them to a verified controller.
    case sendImages(SlideImageRequest, to: Controller)
    /// Applies a controller's command to a presentation.
    case perform(HostCommand, on: PresentationID)
}

/// Decides what the host sends to its verified controllers and which of their commands it
/// applies (REM-04, REM-05). Has no I/O: the app feeds it the open presentations and the
/// controllers' messages and carries out the returned actions in order.
///
/// Only controllers passed to `controllerVerified(_:)` get content or may send commands
/// (REM-06); messages of any other controller are ignored.
public struct RemoteHostState<Controller: Hashable & Sendable>: Sendable {
    public typealias Action = HostAction<Controller>

    private struct ControllerState: Sendable {
        var selection: PresentationID?
        var imageSize = PixelSize(width: 1, height: 1)
        var sentStatus: PresentationStatus?
        var sentImages: SlideImageRequest?
    }

    private var presentations: [HostedPresentation] = []
    /// Verified controllers in the order they were verified, so actions are predictable.
    private var controllerOrder: [Controller] = []
    private var controllers: [Controller: ControllerState] = [:]

    /// The largest image side the host renders, so a controller cannot make it render
    /// huge images. 4096 px is more than any display needs for one slide.
    public static var maxImageSide: Int { 4096 }

    public init() {}

    /// Whether `controller` is verified and still connected.
    public func isVerified(_ controller: Controller) -> Bool {
        controllers[controller] != nil
    }

    /// The presentation `controller` selected, if any.
    public func selection(of controller: Controller) -> PresentationID? {
        controllers[controller]?.selection
    }

    /// A controller proved its pairing key: it gets the list of open presentations.
    public mutating func controllerVerified(_ controller: Controller) -> [Action] {
        if controllers[controller] == nil {
            controllerOrder.append(controller)
        }
        controllers[controller] = ControllerState()
        return [.send(.presentations(presentations.map(\.summary)), to: controller)]
    }

    /// The controller's connection ended or its trust was removed. A pointer it left on its
    /// presentation is hidden.
    public mutating func controllerLeft(_ controller: Controller) -> [Action] {
        let selection = controllers[controller]?.selection
        controllers[controller] = nil
        controllerOrder.removeAll { $0 == controller }
        return selection.map { [.perform(.pointerFinished, on: $0)] } ?? []
    }

    /// The open presentations changed (opened, closed, page, curtain, notes, reload).
    public mutating func update(_ newPresentations: [HostedPresentation]) -> [Action] {
        let listChanged = newPresentations.map(\.summary) != presentations.map(\.summary)
        presentations = newPresentations
        var actions: [Action] = []
        for controller in controllerOrder {
            if listChanged {
                actions.append(.send(.presentations(presentations.map(\.summary)), to: controller))
            }
            actions += refresh(controller)
        }
        return actions
    }

    /// A message of a controller. Ignored unless the controller is verified.
    public mutating func receive(_ message: ControllerMessage, from controller: Controller) -> [Action] {
        guard var state = controllers[controller] else { return [] }
        switch message {
        case .selectPresentation(let id, let size):
            guard presentations.contains(where: { $0.id == id }) else {
                // Closed in the meantime; the controller picks again from the list.
                return [.send(.presentationClosed(id), to: controller)]
            }
            // A pointer left on the previous presentation is hidden.
            let leftPointer: [Action] = state.selection.map { $0 == id ? [] : [.perform(.pointerFinished, on: $0)] } ?? []
            state = ControllerState(selection: id, imageSize: Self.limited(size))
            controllers[controller] = state
            return leftPointer + refresh(controller)
        case .setImageSize(let size):
            state.imageSize = Self.limited(size)
            controllers[controller] = state
            return refresh(controller)
        case .nextSlide: return command(.nextSlide, from: state)
        case .previousSlide: return command(.previousSlide, from: state)
        case .setCurtain(let curtain): return command(.setCurtain(curtain), from: state)
        case .pointerMoved(let position): return command(.pointerMoved(position), from: state)
        case .pointerFinished: return command(.pointerFinished, from: state)
        }
    }

    // MARK: - Private

    /// Scales `size` down, keeping its aspect ratio, so no side exceeds `maxImageSide`.
    private static func limited(_ size: PixelSize) -> PixelSize {
        let longest = max(size.width, size.height)
        guard longest > maxImageSide else { return size }
        let scale = Double(maxImageSide) / Double(longest)
        return PixelSize(width: Int((Double(size.width) * scale).rounded()), height: Int((Double(size.height) * scale).rounded()))
    }

    private func command(_ command: HostCommand, from state: ControllerState) -> [Action] {
        guard let selection = state.selection else { return [] }
        return [.perform(command, on: selection)]
    }

    /// Sends what changed for the controller's selection since the last time.
    private mutating func refresh(_ controller: Controller) -> [Action] {
        guard var state = controllers[controller], let selection = state.selection else { return [] }
        guard let presentation = presentations.first(where: { $0.id == selection }) else {
            controllers[controller] = ControllerState(imageSize: state.imageSize)
            return [.send(.presentationClosed(selection), to: controller)]
        }
        var actions: [Action] = []
        let status = presentation.status
        if status != state.sentStatus {
            state.sentStatus = status
            actions.append(.send(.status(status), to: controller))
        }
        let images = SlideImageRequest(
            presentationID: selection,
            slideIndex: presentation.slideIndex,
            nextSlideIndex: presentation.slideIndex + 1 < presentation.slideCount ? presentation.slideIndex + 1 : nil,
            size: state.imageSize,
            contentVersion: presentation.contentVersion
        )
        if images != state.sentImages {
            state.sentImages = images
            actions.append(.sendImages(images, to: controller))
        }
        controllers[controller] = state
        return actions
    }
}
