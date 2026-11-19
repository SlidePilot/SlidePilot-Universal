import CoreGraphics
import Foundation
import PDFKit

/// A video placed on a page with Beamer's `\movie` (NAV-07).
public struct SlideMovie: Sendable, Hashable {
    /// The video's area as a fraction of the displayed page (`/Rotate` applied), origin top left.
    public let unitRect: CGRect
    /// The file as written in the PDF, usually relative to the PDF (see `LinkedFile`).
    public let reference: String

    public init(unitRect: CGRect, reference: String) {
        self.unitRect = unitRect
        self.reference = reference
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
            /// A `Movie` annotation and its file.
            case movie(String)
            /// A `Link` annotation with a `/Launch` action and its file.
            case launch(String)
        }

        /// In page space, like `PDFAnnotation.bounds`.
        let bounds: CGRect
        let kind: Kind
    }

    static func entries(of page: CGPDFPage) -> [Entry] {
        guard let pageDictionary = page.dictionary else { return [] }
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { return [] }
        return (0..<CGPDFArrayGetCount(annotations)).compactMap { index in
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
                  let bounds = rect(annotation, "Rect")
            else { return nil }
            switch name(annotation, "Subtype") {
            case "Movie":
                var movie: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(annotation, "Movie", &movie), let movie,
                      let file = fileSpecification(movie, "F")
                else { return nil }
                return Entry(bounds: bounds, kind: .movie(file))
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

/// Reads the movies of a page.
enum MovieExtractor {
    static func movies(on page: PDFPage) -> [SlideMovie] {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0, let pageRef = page.pageRef else { return [] }
        return RawAnnotationReader.entries(of: pageRef).compactMap { entry in
            guard case .movie(let reference) = entry.kind else { return nil }
            let rect = LinkExtractor.displayedUnitRect(of: entry.bounds, mediaBox: mediaBox, rotation: page.rotation)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return SlideMovie(unitRect: rect, reference: reference)
        }
    }
}
