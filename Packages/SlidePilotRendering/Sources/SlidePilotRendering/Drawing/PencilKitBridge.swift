import PencilKit
import SlidePilotCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Converts between `PKDrawing` (canvas coordinates of one view) and the relative per-page
/// model (ADR 0016). PencilKit's data types exist on macOS and iPadOS, so this is tested on
/// both; only `PKCanvasView` is iPad-only.
public enum PencilKitBridge {
    /// Distance in canvas points between the samples taken along PencilKit's rendered curve.
    /// PencilKit draws a spline through its control points; sampling the curve keeps that
    /// smooth look in the Core Graphics views.
    public static let sampleSpacing = 2.0

    /// The strokes of `drawing` in relative page coordinates, sampled along the rendered curve.
    public static func strokes(from drawing: PKDrawing, mapping: CanvasMapping) -> [DrawingStroke] {
        guard mapping.isValid else { return [] }
        return drawing.strokes.map { stroke in
            let color = StrokeColor(cgColor: stroke.ink.color.cgColor) ?? .black
            let points = stroke.path
                .interpolatedPoints(by: .distance(sampleSpacing))
                .map { point in
                    let p = point.location.applying(stroke.transform)
                    return mapping.relative(x: p.x, y: p.y)
                }
            // A preset that came back with rounding errors is stored as the exact preset.
            return DrawingStroke(color: color.matchingPreset() ?? color, points: points)
        }
    }

    /// A `PKDrawing` of the strokes of `drawing` for a canvas with `mapping`. `pointSize` is
    /// the size PencilKit gives the points of a monoline stroke of width
    /// `PageDrawing.lineWidth` (4 pt when measured, not 2): rebuilt strokes with smaller
    /// points look thinner than when they were drawn.
    public static func pkDrawing(from drawing: PageDrawing, mapping: CanvasMapping, pointSize: Double) -> PKDrawing {
        guard mapping.isValid else { return PKDrawing() }
        let date = Date()
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            guard !stroke.points.isEmpty else { return nil }
            let controlPoints = stroke.points.enumerated().map { index, point in
                PKStrokePoint(
                    location: mapping.canvasPoint(point),
                    timeOffset: Double(index) / 120,
                    size: CGSize(width: pointSize, height: pointSize),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            let ink = PKInk(.monoline, color: platformColor(stroke.color))
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: date))
        }
        return PKDrawing(strokes: strokes)
    }

    /// The point size PencilKit uses for monoline width 2, before a stroke was measured.
    public static let defaultPointSize = 4.0

    #if os(macOS)
    public static func platformColor(_ c: StrokeColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #else
    public static func platformColor(_ c: StrokeColor) -> UIColor {
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #endif
}
