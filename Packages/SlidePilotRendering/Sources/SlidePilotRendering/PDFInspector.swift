import Foundation
import PDFKit

/// What the app needs to know about a PDF right after opening it.
public struct PDFDocumentInfo: Sendable, Equatable {
    /// Size of every page in points, in its displayed orientation (`/Rotate` applied).
    /// Lets views lay out slides before they are rendered.
    public let pageSizes: [CGSize]

    /// The document's Keywords entry, e.g. `SP-Right` for split notes (NOTES-03).
    public let keywords: [String]

    public var pageCount: Int { pageSizes.count }

    public init(pageSizes: [CGSize], keywords: [String] = []) {
        self.pageSizes = pageSizes
        self.keywords = keywords
    }
}

/// Why a file cannot be presented (DEF-17: the old app failed silently).
public enum PDFOpenError: Error, Sendable, Equatable {
    /// The data cannot be parsed as a PDF (damaged, truncated or another format).
    case notAPDF
    /// The PDF needs a password to be opened.
    case locked
    /// The PDF parses but has no pages to show.
    case noPages
}

/// Checks that opened file data is a PDF that can be presented.
public enum PDFInspector {
    /// Parses `data` and returns its page sizes, or the reason it cannot be presented.
    ///
    /// Runs on any thread: it only reads a `PDFDocument` it owns and lets it go before returning.
    public static func inspect(_ data: Data) throws(PDFOpenError) -> PDFDocumentInfo {
        guard !data.isEmpty, let document = PDFDocument(data: data) else { throw .notAPDF }
        // A user password locks the document; an owner password alone does not.
        guard !document.isLocked else { throw .locked }
        guard document.pageCount > 0 else { throw .noPages }
        let sizes = (0..<document.pageCount).map { index in
            document.page(at: index).map(PageGeometry.displayedSize) ?? .zero
        }
        return PDFDocumentInfo(pageSizes: sizes, keywords: keywords(of: document))
    }

    /// PDFKit returns the Keywords as an array of strings, like the old app read them.
    private static func keywords(of document: PDFDocument) -> [String] {
        let keywords = document.documentAttributes?[PDFDocumentAttribute.keywordsAttribute] as? [Any]
        return keywords?.compactMap { $0 as? String } ?? []
    }
}
