import PencilKit
import SlidePilotCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Converts between `PKDrawing` (canvas coordinates of one view) and the
/// relative per-page model. PencilKit's data types exist on macOS and iPadOS;
/// only `PKCanvasView` and `PKToolPicker` are iPad-only.
public enum PencilKitBridge {
    /// How a PencilKit stroke is sampled into model points.
    public enum Sampling: Sendable {
        /// The stroke's B-spline control points (what PencilKit stores).
        case controlPoints
        /// Points along the rendered curve, `spacing` canvas points apart.
        case interpolated(spacing: Double)
    }

    public static func strokes(
        from drawing: PKDrawing,
        mapping: CanvasMapping,
        sampling: Sampling = .controlPoints
    ) -> [DrawingStroke] {
        drawing.strokes.map { stroke in
            let color = StrokeColor(cgColor: stroke.ink.color.cgColor) ?? .black
            let locations: [CGPoint]
            switch sampling {
            case .controlPoints:
                locations = stroke.path.map(\.location)
            case .interpolated(let spacing):
                locations = stroke.path.interpolatedPoints(by: .distance(spacing)).map(\.location)
            }
            let points = locations.map { location in
                let p = location.applying(stroke.transform)
                return mapping.relative(x: p.x, y: p.y)
            }
            return DrawingStroke(color: color, points: points)
        }
    }

    public static func pkDrawing(
        from drawing: PageDrawing,
        mapping: CanvasMapping,
        lineWidth: Double = PageDrawing.lineWidth
    ) -> PKDrawing {
        let date = Date()
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            guard !stroke.points.isEmpty else { return nil }
            let controlPoints = stroke.points.enumerated().map { index, point in
                let p = mapping.canvas(point)
                return PKStrokePoint(
                    location: CGPoint(x: p.x, y: p.y),
                    timeOffset: Double(index) / 120,
                    size: CGSize(width: lineWidth, height: lineWidth),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            let ink = PKInk(.monoline, color: platformColor(stroke.color))
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: date))
        }
        return PKDrawing(strokes: strokes)
    }

    #if os(macOS)
    private static func platformColor(_ c: StrokeColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #else
    private static func platformColor(_ c: StrokeColor) -> UIColor {
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #endif
}
