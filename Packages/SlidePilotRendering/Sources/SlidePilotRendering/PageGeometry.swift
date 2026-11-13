import CoreGraphics
import PDFKit

/// Page sizes and regions in the displayed orientation (`/Rotate` applied).
///
/// `PDFPage.draw(with:to:)` applies the rotation itself and draws the rotated media box
/// with its origin at (0, 0), so only sizes and regions are computed here.
enum PageGeometry {
    /// Size of the media box in points after applying the page's rotation.
    ///
    /// Reads the page only; never changes its boxes (DEF-02).
    static func displayedSize(of page: PDFPage) -> CGSize {
        displayedSize(mediaBox: page.bounds(for: .mediaBox), rotation: page.rotation)
    }

    static func displayedSize(mediaBox: CGRect, rotation: Int) -> CGSize {
        switch normalized(rotation) {
        case 90, 270: CGSize(width: mediaBox.height, height: mediaBox.width)
        default: mediaBox.size
        }
    }

    /// The region in displayed space with the origin bottom left, as Core Graphics draws.
    static func regionRect(_ region: PageRegion, displayedSize size: CGSize) -> CGRect {
        let unit = region.unitRect
        return CGRect(
            x: unit.minX * size.width,
            y: (1 - unit.maxY) * size.height,
            width: unit.width * size.width,
            height: unit.height * size.height
        )
    }

    private static func normalized(_ rotation: Int) -> Int {
        ((rotation % 360) + 360) % 360
    }
}
