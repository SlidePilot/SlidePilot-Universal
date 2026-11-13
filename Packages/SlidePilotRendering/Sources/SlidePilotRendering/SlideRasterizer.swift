import CoreGraphics
import Foundation
import PDFKit

/// A rendered page region. `CGImage` is immutable, so the value can cross actors.
public struct RenderedSlide: Sendable {
    public let image: CGImage
    public let pageIndex: Int
    public let region: PageRegion

    public var pixelSize: PixelSize {
        PixelSize(width: image.width, height: image.height)
    }

    /// Memory the cache charges for this image. Counted by the cache itself, because
    /// Core Graphics image memory does not show up in the process footprint (ADR 0005).
    var byteCount: Int { image.bytesPerRow * image.height }
}

public enum RenderError: Error, Sendable, Equatable {
    case pageNotFound
    case renderFailed
}

/// Renders pages of its own `PDFDocument`.
///
/// Every worker opens the PDF data itself and keeps it for the session, so no `PDFPage`
/// is ever shared between threads (DEF-02). Pages are only read, never modified: the
/// region is selected with a transform instead of changing the crop box.
actor SlideRasterizer {
    private let data: Data
    /// Opened on the first render, so creating a cache costs nothing until it is used.
    private lazy var document: PDFDocument? = PDFDocument(data: data)

    init(data: Data) {
        self.data = data
    }

    /// Renders `region` of page `index`, aspect-fitted into `box`, on a white background.
    func render(page index: Int, region: PageRegion, fitting box: PixelSize) throws -> RenderedSlide {
        // Queued jobs for pages the presenter has left are cancelled before they start.
        try Task.checkCancellation()
        guard let page = document?.page(at: index) else { throw RenderError.pageNotFound }

        let mediaBox = page.bounds(for: .mediaBox)
        let rotation = page.rotation
        let displayedSize = PageGeometry.displayedSize(mediaBox: mediaBox, rotation: rotation)
        let regionRect = PageGeometry.regionRect(region, displayedSize: displayedSize)
        let pixels = box.aspectFit(regionRect.size)

        // PDFKit autoreleases objects that keep the bitmap alive; without a pool per
        // render, discarded renders piled up to 1.4 GiB in the #8 measurements.
        let image: CGImage? = autoreleasepool {
            guard let context = CGContext(
                data: nil,
                width: pixels.width,
                height: pixels.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }

            context.interpolationQuality = .high
            // PDF pages are drawn on paper white, whatever the app's appearance.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))

            context.scaleBy(
                x: CGFloat(pixels.width) / regionRect.width,
                y: CGFloat(pixels.height) / regionRect.height
            )
            context.translateBy(x: -regionRect.minX, y: -regionRect.minY)
            // PDFKit applies the page's rotation and box origin itself and draws the
            // rotated media box into (0, 0, displayed width, displayed height).
            page.draw(with: .mediaBox, to: context)
            return context.makeImage()
        }
        guard let image else { throw RenderError.renderFailed }
        return RenderedSlide(image: image, pageIndex: index, region: region)
    }
}
