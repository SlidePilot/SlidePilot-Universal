import CoreGraphics
import Foundation
import PDFKit
import SlidePilotCore
import UniformTypeIdentifiers

/// A video placed on a page with Beamer's `\movie` (NAV-07).
public struct SlideMovie: Sendable, Hashable {
    /// The video's area as a fraction of the displayed page (`/Rotate` applied), origin top left.
    public let unitRect: CGRect
    /// The annotation's rectangle in PDF points (page space, as written in the PDF). Tells
    /// whether two overlay build steps show a video at the same place (#140).
    public let bounds: CGRect
    /// The file as written in the PDF, usually relative to the PDF (see `LinkedFile`). For
    /// a video stored inside the PDF, the name it was embedded with.
    public let reference: String
    /// Autostart, loop, start and duration.
    public let activation: MovieActivation
    /// The temporary copy of a video stored inside the PDF (#142); `nil` for a video that
    /// `reference` names.
    public let embeddedFile: URL?

    public init(
        unitRect: CGRect,
        bounds: CGRect,
        reference: String,
        activation: MovieActivation = MovieActivation(),
        embeddedFile: URL? = nil
    ) {
        self.unitRect = unitRect
        self.bounds = bounds
        self.reference = reference
        self.activation = activation
        self.embeddedFile = embeddedFile
    }

    /// The video's file name, for labels.
    public var fileName: String {
        URL(filePath: reference).lastPathComponent
    }

    /// The video's area as a fraction of `region`, origin top left. Not clipped, so the video
    /// keeps its aspect ratio when it reaches past the region; `nil` if it lies outside.
    public func unitRect(in region: PageRegion) -> CGRect? {
        let regionRect = region.unitRect
        let visible = unitRect.intersection(regionRect)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        return CGRect(
            x: (unitRect.minX - regionRect.minX) / regionRect.width,
            y: (unitRect.minY - regionRect.minY) / regionRect.height,
            width: unitRect.width / regionRect.width,
            height: unitRect.height / regionRect.height
        )
    }
}

/// Reads annotations that PDFKit does not describe completely, straight from the page
/// dictionary with Core Graphics.
///
/// Since macOS 27 PDFKit no longer reports the `/Movie` dictionary of a movie annotation
/// (SlidePilot-macOS#89), and it has no public type for `/Launch` actions (`run:` links).
enum RawAnnotationReader {
    struct Entry {
        enum Kind: Equatable {
            /// A `Movie` annotation, its file and how it plays. `embedded` is the video's
            /// stream when the PDF stores it (`/EF`); the file name is then only its name.
            case movie(String, MovieActivation, embedded: CGPDFStreamRef?)
            /// A `Link` annotation with a `/Launch` action and its file.
            case launch(String)
        }

        /// In page space, like `PDFAnnotation.bounds`.
        let bounds: CGRect
        let kind: Kind
    }

    static func entries(of page: CGPDFPage) -> [Entry] {
        guard let pageDictionary = page.dictionary else { return [] }
        var annotationArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotationArray), let annotationArray else { return [] }
        let annotations: [CGPDFDictionaryRef] = (0..<CGPDFArrayGetCount(annotationArray)).compactMap { index in
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &annotation) else { return nil }
            return annotation
        }
        let autostart = autostartTargets(page: pageDictionary, annotations: annotations)
        return annotations.compactMap { annotation in
            guard let bounds = rect(annotation, "Rect") else { return nil }
            switch name(annotation, "Subtype") {
            case "Movie":
                var movie: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(annotation, "Movie", &movie), let movie,
                      let file = fileSpecification(movie, "F")
                else { return nil }
                var activation = activation(of: annotation)
                activation.autostarts = autostart.contains(annotation: annotation, title: string(annotation, "T"))
                return Entry(bounds: bounds, kind: .movie(file, activation, embedded: embeddedFile(movie, "F")))
            case "Link":
                var action: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(annotation, "A", &action), let action,
                      name(action, "S") == "Launch",
                      let file = launchFile(action)
                else { return nil }
                return Entry(bounds: bounds, kind: .launch(file))
            default:
                return nil
            }
        }
    }

    // MARK: - Movie activation

    /// The movies that the page plays when it opens, by title or by annotation.
    struct AutostartTargets {
        var titles: Set<String> = []
        var annotations: [CGPDFDictionaryRef] = []

        func contains(annotation: CGPDFDictionaryRef, title: String?) -> Bool {
            if let title, titles.contains(title) { return true }
            return annotations.contains(annotation)
        }
    }

    /// Movie actions with the operation Play that run when the page opens: Beamer puts one
    /// in a hidden widget's `/AA /PO` (pdfTeX), the pdfmark route in the page's `/AA /O`.
    static func autostartTargets(page: CGPDFDictionaryRef, annotations: [CGPDFDictionaryRef]) -> AutostartTargets {
        var targets = AutostartTargets()
        var actions: [CGPDFDictionaryRef] = []
        if let action = additionalAction(page, "O") { actions.append(action) }
        actions += annotations.compactMap { additionalAction($0, "PO") }
        for action in actions {
            collectPlayActions(action, depth: 0, into: &targets)
        }
        return targets
    }

    /// The action under `/AA /<trigger>`.
    private static func additionalAction(_ dictionary: CGPDFDictionaryRef, _ trigger: String) -> CGPDFDictionaryRef? {
        var additional: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "AA", &additional), let additional else { return nil }
        var action: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(additional, trigger, &action) else { return nil }
        return action
    }

    /// Adds the movie that `action` plays, then follows `/Next` (a dictionary or an array).
    /// The depth limit guards against cyclic chains.
    private static func collectPlayActions(_ action: CGPDFDictionaryRef, depth: Int, into targets: inout AutostartTargets) {
        guard depth < 8 else { return }
        // An omitted operation means Play; Stop, Pause and Resume do not start a video.
        if name(action, "S") == "Movie", (name(action, "Operation") ?? "Play") == "Play" {
            var annotation: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(action, "Annotation", &annotation), let annotation {
                targets.annotations.append(annotation)
            } else if let title = string(action, "T") {
                targets.titles.insert(title)
            }
        }
        var next: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(action, "Next", &next), let next {
            collectPlayActions(next, depth: depth + 1, into: &targets)
            return
        }
        var nextArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(action, "Next", &nextArray), let nextArray else { return }
        for index in 0..<CGPDFArrayGetCount(nextArray) {
            var element: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(nextArray, index, &element), let element {
                collectPlayActions(element, depth: depth + 1, into: &targets)
            }
        }
    }

    /// The movie activation dictionary `/A`: `/Mode`, `/Start` and `/Duration`. It may also be
    /// a boolean, which carries none of these.
    static func activation(of annotation: CGPDFDictionaryRef) -> MovieActivation {
        var result = MovieActivation()
        var activation: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(annotation, "A", &activation), let activation else { return result }
        result.mode = switch name(activation, "Mode") {
        case "Open": .open
        case "Repeat": .repeat
        case "Palindrome": .palindrome
        default: .once
        }
        result.start = time(activation, "Start")
        result.duration = time(activation, "Duration")
        return result
    }

    /// A PDF time in seconds: a number, an 8-byte big-endian integer string, or an array of
    /// one of these and a time scale (units per second). Beamer writes `[<value> 128]`.
    private static func time(_ dictionary: CGPDFDictionaryRef, _ key: String) -> TimeInterval? {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, key, &object), let object else { return nil }
        if let value = timeValue(object) { return MovieActivation.seconds(value) }
        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(object, .array, &array), let array, CGPDFArrayGetCount(array) == 2 else { return nil }
        var valueObject: CGPDFObjectRef?
        var scale: CGPDFReal = 0
        guard CGPDFArrayGetObject(array, 0, &valueObject), let valueObject, let value = timeValue(valueObject),
              CGPDFArrayGetNumber(array, 1, &scale)
        else { return nil }
        return MovieActivation.seconds(value, scale: Double(scale))
    }

    private static func timeValue(_ object: CGPDFObjectRef) -> Double? {
        var number: CGPDFReal = 0
        if CGPDFObjectGetValue(object, .real, &number) { return Double(number) }
        var string: CGPDFStringRef?
        guard CGPDFObjectGetValue(object, .string, &string), let string,
              CGPDFStringGetLength(string) == 8, let bytes = CGPDFStringGetBytePtr(string)
        else { return nil }
        let value = (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(bytes[$1]) }
        return Double(value)
    }

    // MARK: - Embedded files

    /// The embedded file stream of the file specification under `key`: `/EF /UF`, else
    /// `/EF /F`.
    private static func embeddedFile(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var specification: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, key, &specification), let specification else { return nil }
        var files: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(specification, "EF", &files), let files else { return nil }
        for fileKey in ["UF", "F"] {
            var stream: CGPDFStreamRef?
            if CGPDFDictionaryGetStream(files, fileKey, &stream), let stream { return stream }
        }
        return nil
    }

    /// The decoded bytes of an embedded file, and the file extension that tells AVFoundation
    /// its type: from `name`, else from the stream's MIME type (`/Subtype`).
    static func embeddedData(_ stream: CGPDFStreamRef, name: String) -> (data: Data, fileExtension: String)? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw, !data.isEmpty else { return nil }
        var fileExtension = URL(filePath: name).pathExtension
        if fileExtension.isEmpty, let streamDictionary = CGPDFStreamGetDictionary(stream),
           let mimeType = Self.name(streamDictionary, "Subtype") {
            fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? ""
        }
        return (data, fileExtension)
    }

    // MARK: - Helpers

    /// `/F`, or the platform entries `/Unix` and `/Mac` of older writers.
    private static func launchFile(_ action: CGPDFDictionaryRef) -> String? {
        if let file = fileSpecification(action, "F") { return file }
        for platform in ["Unix", "Mac"] {
            if let file = fileSpecification(action, platform) { return file }
            var dictionary: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(action, platform, &dictionary), let dictionary,
               let file = fileSpecification(dictionary, "F") {
                return file
            }
        }
        return nil
    }

    /// A file specification: a string, or a dictionary with `/UF` (Unicode) or `/F`.
    private static func fileSpecification(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        if let string = string(dictionary, key) { return string }
        var specification: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, key, &specification), let specification else { return nil }
        return string(specification, "UF") ?? string(specification, "F")
    }

    private static func string(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value,
              let text = CGPDFStringCopyTextString(value) as String?, !text.isEmpty
        else { return nil }
        return text
    }

    private static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    private static func rect(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGRect? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array, CGPDFArrayGetCount(array) == 4 else { return nil }
        var numbers = [CGFloat]()
        for index in 0..<4 {
            var number: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &number) else { return nil }
            numbers.append(number)
        }
        // Writers may give any two opposite corners.
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1]).standardized
    }
}

/// A movie as read from the page, with the bytes of a video stored inside the PDF.
struct ExtractedMovie: Sendable {
    struct Embedded: Sendable {
        let data: Data
        let fileExtension: String
    }

    let movie: SlideMovie
    /// `nil` for a video that the movie's reference names.
    let embedded: Embedded?

    /// The movie with the temporary copy of its embedded video; `nil` when the copy could
    /// not be written, so the poster stays.
    func storing(in store: EmbeddedFileStore) async -> SlideMovie? {
        guard let embedded else { return movie }
        do {
            let file = try await store.file(for: embedded.data, fileExtension: embedded.fileExtension)
            return SlideMovie(
                unitRect: movie.unitRect,
                bounds: movie.bounds,
                reference: movie.reference,
                activation: movie.activation,
                embeddedFile: file
            )
        } catch {
            return nil
        }
    }
}

/// Reads the movies of a page.
enum MovieExtractor {
    static func movies(on page: PDFPage) -> [ExtractedMovie] {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0, let pageRef = page.pageRef else { return [] }
        return RawAnnotationReader.entries(of: pageRef).compactMap { entry in
            guard case .movie(let reference, let activation, let stream) = entry.kind else { return nil }
            let rect = LinkExtractor.displayedUnitRect(of: entry.bounds, mediaBox: mediaBox, rotation: page.rotation)
            guard rect.width > 0, rect.height > 0 else { return nil }
            var embedded: ExtractedMovie.Embedded?
            if let stream {
                // An embedded video that cannot be read never falls back to a file of that
                // name next to the PDF.
                guard let (data, fileExtension) = RawAnnotationReader.embeddedData(stream, name: reference) else { return nil }
                embedded = ExtractedMovie.Embedded(data: data, fileExtension: fileExtension)
            }
            let movie = SlideMovie(unitRect: rect, bounds: entry.bounds, reference: reference, activation: activation)
            return ExtractedMovie(movie: movie, embedded: embedded)
        }
    }
}
