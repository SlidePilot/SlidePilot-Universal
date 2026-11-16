import CoreGraphics
import SlidePilotCore

/// Draws a `PageDrawing` with Core Graphics. Used for every read-only view
/// (presentation, previews, thumbnails) and for the custom drawing layer.
public enum DrawingRenderer {
    /// `context` must have a top-left origin and the size of the mapping's canvas.
    public static func draw(
        _ drawing: PageDrawing,
        in context: CGContext,
        mapping: CanvasMapping,
        lineWidth: Double = PageDrawing.lineWidth
    ) {
        if drawing.background == .white {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: mapping.canvasWidth, height: mapping.canvasHeight))
        }
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in drawing.strokes {
            draw(stroke, in: context, mapping: mapping)
        }
    }

    public static func draw(_ stroke: DrawingStroke, in context: CGContext, mapping: CanvasMapping) {
        guard let first = stroke.points.first else { return }
        let path = CGMutablePath()
        let start = mapping.canvas(first)
        path.move(to: CGPoint(x: start.x, y: start.y))
        if stroke.points.count == 1 {
            // A tap draws a dot.
            path.addLine(to: CGPoint(x: start.x, y: start.y))
        }
        for point in stroke.points.dropFirst() {
            let p = mapping.canvas(point)
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        context.addPath(path)
        context.setStrokeColor(stroke.color.cgColor)
        context.strokePath()
    }
}

extension StrokeColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public init?(cgColor: CGColor) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4
        else { return nil }
        self.init(red: c[0], green: c[1], blue: c[2], alpha: c[3])
    }
}
