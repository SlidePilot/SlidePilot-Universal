import Foundation
import PDFKit

/// What the app needs to know about a PDF right after opening it.
public struct PDFDocumentInfo: Sendable, Equatable {
    /// Size of every page in points, in its displayed orientation (`/Rotate` applied).
    /// Lets views lay out slides before they are rendered.
    public let pageSizes: [CGSize]

    public var pageCount: Int { pageSizes.count }

    public init(pageSizes: [CGSize]) {
        self.pageSizes = pageSizes
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
        return PDFDocumentInfo(pageSizes: sizes)
    }
}
