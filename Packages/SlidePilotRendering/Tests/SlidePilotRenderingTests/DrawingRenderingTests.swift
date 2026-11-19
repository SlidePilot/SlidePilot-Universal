import CoreGraphics
import PencilKit
import SlidePilotCore
import Testing
@testable import SlidePilotRendering

@Suite struct DrawingRendererTests {
    /// A 100 × 100 RGBA bitmap with a top-left origin, like a view's context.
    private func render(_ drawing: PageDrawing, liveStroke: DrawingStroke? = nil) throws -> [UInt8] {
        let size = 100
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: CGFloat(size))
            context.scaleBy(x: 1, y: -1)
            DrawingRenderer.draw(
                drawing, liveStroke: liveStroke, in: context,
                mapping: CanvasMapping(canvasWidth: Double(size), canvasHeight: Double(size)),
                lineWidth: 4
            )
        }
        return pixels
    }

    /// RGBA at (x, y), top-left origin.
    private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let index = (y * 100 + x) * 4
        return Array(pixels[index..<index + 4])
    }

    private func horizontalLine(atY y: Double, color: StrokeColor) -> DrawingStroke {
        DrawingStroke(color: color, points: [RelativePoint(x: 0.1, y: y), RelativePoint(x: 0.9, y: y)])
    }

    @Test func transparentCanvasLeavesTheSlideVisible() throws {
        let pixels = try render(PageDrawing(strokes: [horizontalLine(atY: 0.5, color: .black)]))
        #expect(pixel(pixels, 50, 10) == [0, 0, 0, 0])
        #expect(pixel(pixels, 50, 50) == [0, 0, 0, 255])
    }

    @Test func whiteCanvasCoversTheSlide() throws {
        let pixels = try render(PageDrawing(strokes: [horizontalLine(atY: 0.5, color: .black)], background: .white))
        #expect(pixel(pixels, 50, 10) == [255, 255, 255, 255])
        #expect(pixel(pixels, 50, 50) == [0, 0, 0, 255])
    }

    // DEF-15: a stroke that cannot be drawn does not stop the following ones.
    @Test func emptyStrokeDoesNotStopLaterStrokes() throws {
        let drawing = PageDrawing(strokes: [
            DrawingStroke(color: .black, points: []),
            horizontalLine(atY: 0.5, color: .white),
        ])
        let pixels = try render(drawing)
        #expect(pixel(pixels, 50, 50) == [255, 255, 255, 255])
    }

    @Test func liveStrokeIsDrawnOnTop() throws {
        let pixels = try render(PageDrawing(), liveStroke: horizontalLine(atY: 0.2, color: .white))
        #expect(pixel(pixels, 50, 20) == [255, 255, 255, 255])
    }

    @Test func singlePointIsADot() throws {
        let dot = DrawingStroke(color: .black, points: [RelativePoint(x: 0.5, y: 0.5)])
        #expect(DrawingRenderer.path(of: dot, mapping: CanvasMapping(canvasWidth: 10, canvasHeight: 10)) != nil)
        let pixels = try render(PageDrawing(strokes: [dot]))
        #expect(pixel(pixels, 50, 50)[3] == 255)
    }

    @Test func colorRoundTripsThroughCGColor() {
        for preset in StrokeColor.presets {
            let back = StrokeColor(cgColor: preset.cgColor)
            #expect(back?.matchingPreset() == preset)
        }
    }

    @Test func regionSections() {
        #expect(PageRegion.full.drawingSection == .fullPage)
        #expect(PageRegion.rightHalf.drawingSection == RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(PageRegion.bottomHalf.drawingSection == RelativeRect(x: 0, y: 0.5, width: 1, height: 0.5))
    }
}

@Suite struct PencilKitBridgeTests {
    private let drawing = PageDrawing(strokes: [
        DrawingStroke(color: .magenta, points: [
            RelativePoint(x: 0.6, y: 0.2), RelativePoint(x: 0.7, y: 0.25), RelativePoint(x: 0.8, y: 0.4),
        ]),
        DrawingStroke(color: .orange, points: [RelativePoint(x: 0.9, y: 0.9), RelativePoint(x: 0.95, y: 0.5)]),
    ])

    // The canvas shows the right half of a split-notes page (DRAW-02).
    private let mapping = CanvasMapping(
        section: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1), canvasWidth: 512, canvasHeight: 768
    )

    @Test func roundTripKeepsColorsAndEndPoints() throws {
        let pk = PencilKitBridge.pkDrawing(from: drawing, mapping: mapping, pointSize: PencilKitBridge.defaultPointSize)
        #expect(pk.strokes.count == 2)
        let back = PencilKitBridge.strokes(from: pk, mapping: mapping)
        #expect(back.map(\.color) == [.magenta, .orange])
        for (original, converted) in zip(drawing.strokes, back) {
            let first = try #require(converted.points.first)
            let last = try #require(converted.points.last)
            #expect(abs(first.x - original.points[0].x) < 0.002)
            #expect(abs(first.y - original.points[0].y) < 0.002)
            #expect(abs(last.x - original.points.last!.x) < 0.002)
            #expect(abs(last.y - original.points.last!.y) < 0.002)
            // Sampled along the curve: never fewer points than drawn.
            #expect(converted.points.count >= original.points.count)
            // All points stay in the section that the canvas shows.
            #expect(converted.points.allSatisfy { $0.x >= 0.5 - 0.002 })
        }
    }

    @Test func rebuiltStrokesUseThePointSize() throws {
        let pk = PencilKitBridge.pkDrawing(from: drawing, mapping: mapping, pointSize: 4)
        let size = try #require(pk.strokes.first?.path.first?.size)
        #expect(size == CGSize(width: 4, height: 4))
    }

    @Test func invalidMappingGivesNothing() {
        let empty = CanvasMapping(canvasWidth: 0, canvasHeight: 0)
        #expect(PencilKitBridge.pkDrawing(from: drawing, mapping: empty, pointSize: 4).strokes.isEmpty)
        #expect(PencilKitBridge.strokes(from: PKDrawing(), mapping: empty).isEmpty)
    }
}
