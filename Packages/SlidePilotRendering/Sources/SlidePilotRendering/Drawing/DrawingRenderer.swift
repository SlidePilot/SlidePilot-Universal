import CoreGraphics
import SlidePilotCore

/// Draws a `PageDrawing` with Core Graphics (ADR 0016). Used by every read-only view
/// (presentation, next-slide preview, thumbnails) and by the Mac drawing layer.
public enum DrawingRenderer {
    /// Draws the background and the strokes. `context` must have a top-left origin and the
    /// size of the mapping's canvas. Strokes that cannot be drawn are skipped; the others are
    /// still drawn (the old app stopped at the first one, DEF-15).
    public static func draw(
        _ drawing: PageDrawing,
        liveStroke: DrawingStroke? = nil,
        in context: CGContext,
        mapping: CanvasMapping,
        lineWidth: Double = PageDrawing.lineWidth
    ) {
        guard mapping.isValid else { return }
        if drawing.background == .white {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: mapping.canvasWidth, height: mapping.canvasHeight))
        }
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in drawing.strokes {
            draw(stroke, in: context, mapping: mapping)
        }
        if let liveStroke {
            draw(liveStroke, in: context, mapping: mapping)
        }
        context.restoreGState()
    }

    /// The path of one stroke on the canvas, `nil` for a stroke without points. A single
    /// point (a tap) becomes a dot.
    public static func path(of stroke: DrawingStroke, mapping: CanvasMapping) -> CGPath? {
        guard mapping.isValid, let first = stroke.points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: mapping.canvasPoint(first))
        if stroke.points.count == 1 {
            path.addLine(to: mapping.canvasPoint(first))
        }
        for point in stroke.points.dropFirst() {
            path.addLine(to: mapping.canvasPoint(point))
        }
        return path
    }

    private static func draw(_ stroke: DrawingStroke, in context: CGContext, mapping: CanvasMapping) {
        guard let path = path(of: stroke, mapping: mapping) else { return }
        context.addPath(path)
        context.setStrokeColor(stroke.color.cgColor)
        context.strokePath()
    }
}

extension CanvasMapping {
    /// `canvas(_:)` as a `CGPoint`.
    public func canvasPoint(_ point: RelativePoint) -> CGPoint {
        let p = canvas(point)
        return CGPoint(x: p.x, y: p.y)
    }
}

extension StrokeColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// The color in sRGB, `nil` if it cannot be converted.
    public init?(cgColor: CGColor) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4
        else { return nil }
        self.init(red: c[0], green: c[1], blue: c[2], alpha: c[3])
    }
}

extension PageRegion {
    /// The part of the page a canvas over this region shows (DRAW-02).
    public var drawingSection: RelativeRect {
        let rect = unitRect
        return RelativeRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
