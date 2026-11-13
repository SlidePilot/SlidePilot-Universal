import CoreGraphics

/// The part of a PDF page that a slide surface shows.
///
/// Split-notes decks put the slide and the notes on one page; the presenter shows one half
/// to the audience and the other half as notes. Halves are measured in the page's displayed
/// orientation (after `/Rotate`), so "left" is always the left half the user sees.
public enum PageRegion: Sendable, Hashable, CaseIterable {
    case full
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf

    /// The region as a fraction of the displayed page, origin top left.
    public var unitRect: CGRect {
        switch self {
        case .full: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        }
    }

    /// Size in points of this region on a page whose displayed size is `pageSize`.
    public func size(onPageOfSize pageSize: CGSize) -> CGSize {
        CGSize(width: pageSize.width * unitRect.width, height: pageSize.height * unitRect.height)
    }
}

/// Pixel dimensions of a rendered image or of the box it must fit into.
public struct PixelSize: Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Whether an image of this size can be scaled down to `other` without upscaling.
    public func covers(_ other: PixelSize) -> Bool {
        width >= other.width && height >= other.height
    }

    /// The largest size with the aspect ratio of `contentSize` that fits into `self`, at least 1×1.
    public func aspectFit(_ contentSize: CGSize) -> PixelSize {
        guard contentSize.width > 0, contentSize.height > 0, width > 0, height > 0 else {
            return PixelSize(width: 1, height: 1)
        }
        let scale = min(Double(width) / contentSize.width, Double(height) / contentSize.height)
        return PixelSize(
            width: max(1, Int((contentSize.width * scale).rounded())),
            height: max(1, Int((contentSize.height * scale).rounded()))
        )
    }
}
