import Foundation

/// Identifies one open presentation (document) of a host. A host with several open
/// documents offers each of them (DOC-01, ADR 0015).
public struct PresentationID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One entry of the host's list of open presentations.
public struct PresentationSummary: Codable, Sendable, Hashable {
    public let id: PresentationID
    /// The document's display name.
    public let title: String
    public let slideCount: Int

    public init(id: PresentationID, title: String, slideCount: Int) {
        self.id = id
        self.title = title
        self.slideCount = slideCount
    }
}

/// What the presentation display shows instead of the slide.
public enum RemoteCurtain: String, Codable, Sendable {
    case none, black, white
}

/// Meta and notes of the selected presentation (REM-04).
public struct PresentationStatus: Codable, Sendable, Equatable {
    public let presentationID: PresentationID
    /// Zero-based index of the current slide.
    public let slideIndex: Int
    public let slideCount: Int
    public let curtain: RemoteCurtain
    /// Text notes of the current slide as RTF, so formatting survives (NOTES-04); `nil` if
    /// the document has no text notes.
    public let notesRTF: Data?

    public init(presentationID: PresentationID, slideIndex: Int, slideCount: Int, curtain: RemoteCurtain, notesRTF: Data?) {
        self.presentationID = presentationID
        self.slideIndex = slideIndex
        self.slideCount = slideCount
        self.curtain = curtain
        self.notesRTF = notesRTF
    }

    /// One-based slide number as shown to the user.
    public var slideNumber: Int { slideIndex + 1 }
}

public enum ImageFormat: String, Codable, Sendable {
    case jpeg, heic
}

/// A compressed slide image. The host sends at least the requested size (PRE-02); the
/// controller scales it down itself.
public struct EncodedImage: Codable, Sendable, Equatable {
    public let format: ImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let data: Data

    public init(format: ImageFormat, pixelWidth: Int, pixelHeight: Int, data: Data) {
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.data = data
    }
}

/// The images of one slide, sent together so the controller never mixes slides (REM-04).
public struct SlideImages: Codable, Sendable, Equatable {
    public let presentationID: PresentationID
    public let slideIndex: Int
    /// The slide as the audience sees it.
    public let current: EncodedImage
    /// The following slide; `nil` on the last slide, where the controller shows black.
    public let next: EncodedImage?
    /// The notes half of the page in split notes mode; `nil` otherwise.
    public let notes: EncodedImage?

    public init(presentationID: PresentationID, slideIndex: Int, current: EncodedImage, next: EncodedImage?, notes: EncodedImage?) {
        self.presentationID = presentationID
        self.slideIndex = slideIndex
        self.current = current
        self.next = next
        self.notes = notes
    }
}

/// Size in pixels the controller wants slide images in.
public struct PixelSize: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int

    /// Clamped to at least 1×1 pixel.
    public init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(width: try container.decode(Int.self, forKey: .width),
                  height: try container.decode(Int.self, forKey: .height))
    }

    private enum CodingKeys: String, CodingKey { case width, height }
}

/// Pointer position relative to the slide: 0…1 on both axes, origin top left.
public struct PointerPosition: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    /// Clamped to the slide; a non-finite value becomes 0.
    public init(x: Double, y: Double) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(Double.self, forKey: .x),
                  y: try container.decode(Double.self, forKey: .y))
    }

    private enum CodingKeys: String, CodingKey { case x, y }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

// MARK: - Host → controller

/// Messages a host sends to a verified controller (REM-04).
public enum HostMessage: RemoteWireMessage, Equatable {
    /// All open presentations. Sent after verification and whenever the list changes.
    case presentations([PresentationSummary])
    /// Meta and notes of the selected presentation. Sent on selection, page change,
    /// curtain change, notes edit and reload.
    case status(PresentationStatus)
    /// Images of the current slide. Sent on selection, page change, notes position change
    /// and reload.
    case slideImages(SlideImages)
    /// The selected presentation was closed on the host.
    case presentationClosed(PresentationID)
    /// The host user removed this controller from the trusted devices (REM-03); the host
    /// closes the connection next. The controller deletes its key and stops reconnecting.
    /// Only a verified host can send it, so a stranger cannot remove trust (DEF-04).
    case trustRemoved

    public static let sender = RemoteRole.host

    private enum Kind: String {
        case presentations, status, slideImages, presentationClosed, trustRemoved
    }

    public func wireData() throws(RemoteProtocolError) -> Data {
        switch self {
        case .presentations(let list): try Wire.encode(type: Kind.presentations.rawValue, payload: list)
        case .status(let status): try Wire.encode(type: Kind.status.rawValue, payload: status)
        case .slideImages(let images): try Wire.encode(type: Kind.slideImages.rawValue, payload: images)
        case .presentationClosed(let id): try Wire.encode(type: Kind.presentationClosed.rawValue, payload: id)
        case .trustRemoved: try Wire.encode(type: Kind.trustRemoved.rawValue)
        }
    }

    public static func fromWire(_ data: Data) throws(RemoteProtocolError) -> HostMessage? {
        guard let kind = Kind(rawValue: try Wire.type(of: data)) else { return nil }
        return switch kind {
        case .presentations: .presentations(try Wire.payload([PresentationSummary].self, from: data))
        case .status: .status(try Wire.payload(PresentationStatus.self, from: data))
        case .slideImages: .slideImages(try Wire.payload(SlideImages.self, from: data))
        case .presentationClosed: .presentationClosed(try Wire.payload(PresentationID.self, from: data))
        case .trustRemoved: .trustRemoved
        }
    }
}

// MARK: - Controller → host

/// Messages a verified controller sends to the host (REM-05).
public enum ControllerMessage: RemoteWireMessage, Equatable {
    /// Picks one of the offered presentations; the host answers with status and images.
    case selectPresentation(PresentationID, imageSize: PixelSize)
    /// The controller's slide area changed size.
    case setImageSize(PixelSize)
    case nextSlide
    case previousSlide
    case setCurtain(RemoteCurtain)
    case pointerMoved(PointerPosition)
    case pointerFinished

    public static let sender = RemoteRole.controller

    private enum Kind: String {
        case selectPresentation, setImageSize, nextSlide, previousSlide, setCurtain, pointerMoved, pointerFinished
    }

    private struct Selection: Codable {
        let presentationID: PresentationID
        let imageSize: PixelSize
    }

    public func wireData() throws(RemoteProtocolError) -> Data {
        switch self {
        case .selectPresentation(let id, let size):
            try Wire.encode(type: Kind.selectPresentation.rawValue, payload: Selection(presentationID: id, imageSize: size))
        case .setImageSize(let size): try Wire.encode(type: Kind.setImageSize.rawValue, payload: size)
        case .nextSlide: try Wire.encode(type: Kind.nextSlide.rawValue)
        case .previousSlide: try Wire.encode(type: Kind.previousSlide.rawValue)
        case .setCurtain(let curtain): try Wire.encode(type: Kind.setCurtain.rawValue, payload: curtain)
        case .pointerMoved(let position): try Wire.encode(type: Kind.pointerMoved.rawValue, payload: position)
        case .pointerFinished: try Wire.encode(type: Kind.pointerFinished.rawValue)
        }
    }

    public static func fromWire(_ data: Data) throws(RemoteProtocolError) -> ControllerMessage? {
        guard let kind = Kind(rawValue: try Wire.type(of: data)) else { return nil }
        switch kind {
        case .selectPresentation:
            let selection = try Wire.payload(Selection.self, from: data)
            return .selectPresentation(selection.presentationID, imageSize: selection.imageSize)
        case .setImageSize: return .setImageSize(try Wire.payload(PixelSize.self, from: data))
        case .nextSlide: return .nextSlide
        case .previousSlide: return .previousSlide
        case .setCurtain: return .setCurtain(try Wire.payload(RemoteCurtain.self, from: data))
        case .pointerMoved: return .pointerMoved(try Wire.payload(PointerPosition.self, from: data))
        case .pointerFinished: return .pointerFinished
        }
    }
}
