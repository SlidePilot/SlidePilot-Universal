import CoreGraphics
import Foundation
import PDFKit

/// A clickable link on a PDF page: an internal jump or a URL (NAV-05), or a file (NAV-06).
public struct SlideLink: Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        /// Zero-based index of the page an internal link (`PDFActionGoTo`) jumps to.
        case page(Int)
        /// A URL link (`PDFActionURL`), opened in the default app.
        case url(URL)
        /// A `\href{run:…}` link (`/Launch` action): the file as written in the PDF, usually
        /// relative to the PDF (see `LinkedFile` in Core).
        case file(String)
    }

    /// The link area as a fraction of the displayed page (`/Rotate` applied), origin top left.
    public let unitRect: CGRect
    public let target: Target

    public init(unitRect: CGRect, target: Target) {
        self.unitRect = unitRect
        self.target = target
    }

    /// The link area as a fraction of `region`, origin top left, clipped to the region.
    /// `nil` if the link lies outside the region (e.g. on the notes half of a split page).
    public func unitRect(in region: PageRegion) -> CGRect? {
        let regionRect = region.unitRect
        let visible = unitRect.intersection(regionRect)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        return CGRect(
            x: (visible.minX - regionRect.minX) / regionRect.width,
            y: (visible.minY - regionRect.minY) / regionRect.height,
            width: visible.width / regionRect.width,
            height: visible.height / regionRect.height
        )
    }
}

/// Reads the link annotations of a page.
enum LinkExtractor {
    /// The internal, URL and `run:` links of `page`. Other annotations, links without a
    /// usable target and links whose target page is not in `document` are skipped, like the
    /// old app did on click (`PDFPageView.mouseDown`).
    static func links(on page: PDFPage, in document: PDFDocument) -> [SlideLink] {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return [] }
        let pdfKitLinks: [SlideLink] = page.annotations.compactMap { annotation in
            // `type` is the subtype without the slash; only links get the pointing hand.
            guard annotation.type == "Link" else { return nil }
            let target: SlideLink.Target
            if let goTo = annotation.action as? PDFActionGoTo {
                guard let destinationPage = goTo.destination.page else { return nil }
                let index = document.index(for: destinationPage)
                guard index >= 0, index < document.pageCount else { return nil }
                target = .page(index)
            } else if let urlAction = annotation.action as? PDFActionURL {
                // PDFKit reports `/Launch` as a URL action, resolved against the document's
                // URL, which a PDF opened from data does not have. Read below instead.
                guard urlAction.type != "Launch", let url = urlAction.url else { return nil }
                // A `file:` link goes through the same checks as a `run:` link (NAV-06).
                target = url.isFileURL ? .file(url.path(percentEncoded: false)) : .url(url)
            } else {
                return nil
            }
            let rect = displayedUnitRect(of: annotation.bounds, mediaBox: mediaBox, rotation: page.rotation)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return SlideLink(unitRect: rect, target: target)
        }
        guard let pageRef = page.pageRef else { return pdfKitLinks }
        let runLinks: [SlideLink] = RawAnnotationReader.entries(of: pageRef).compactMap { entry in
            guard case .launch(let reference) = entry.kind else { return nil }
            let rect = displayedUnitRect(of: entry.bounds, mediaBox: mediaBox, rotation: page.rotation)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return SlideLink(unitRect: rect, target: .file(reference))
        }
        return pdfKitLinks + runLinks
    }

    /// Maps a rectangle in page space (unrotated, origin bottom left of the media box) to
    /// a fraction of the displayed page (rotated clockwise by `rotation`, origin top left).
    static func displayedUnitRect(of bounds: CGRect, mediaBox: CGRect, rotation: Int) -> CGRect {
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ].map { point in
            displayedUnitPoint(
                CGPoint(x: (point.x - mediaBox.minX) / mediaBox.width, y: (point.y - mediaBox.minY) / mediaBox.height),
                rotation: rotation
            )
        }
        let minX = Swift.max(0, corners.map(\.x).min() ?? 0)
        let minY = Swift.max(0, corners.map(\.y).min() ?? 0)
        let maxX = Swift.min(1, corners.map(\.x).max() ?? 0)
        let maxY = Swift.min(1, corners.map(\.y).max() ?? 0)
        return CGRect(x: minX, y: minY, width: Swift.max(0, maxX - minX), height: Swift.max(0, maxY - minY))
    }

    /// `point` is a fraction of the unrotated page with the origin bottom left.
    private static func displayedUnitPoint(_ point: CGPoint, rotation: Int) -> CGPoint {
        let (u, v) = (point.x, point.y)
        // `/Rotate` turns the page clockwise.
        switch ((rotation % 360) + 360) % 360 {
        case 90: return CGPoint(x: v, y: u)
        case 180: return CGPoint(x: 1 - u, y: v)
        case 270: return CGPoint(x: 1 - v, y: 1 - u)
        default: return CGPoint(x: u, y: 1 - v)
        }
    }
}
