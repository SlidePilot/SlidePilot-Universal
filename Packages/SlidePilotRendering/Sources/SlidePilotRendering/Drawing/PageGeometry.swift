import CoreGraphics
import SlidePilotCore

/// Converts relative points (top-left origin of the page as displayed, i.e.
/// after `/Rotate`) into PDF page space (bottom-left origin, unrotated).
public enum PageGeometry {
    public static func pagePoint(_ point: RelativePoint, box: CGRect, rotation: Int) -> CGPoint {
        let w = box.width, h = box.height
        switch ((rotation % 360) + 360) % 360 {
        case 90: return CGPoint(x: box.minX + point.y * w, y: box.minY + point.x * h)
        case 180: return CGPoint(x: box.maxX - point.x * w, y: box.minY + point.y * h)
        case 270: return CGPoint(x: box.maxX - point.y * w, y: box.maxY - point.x * h)
        default: return CGPoint(x: box.minX + point.x * w, y: box.maxY - point.y * h)
        }
    }
}
