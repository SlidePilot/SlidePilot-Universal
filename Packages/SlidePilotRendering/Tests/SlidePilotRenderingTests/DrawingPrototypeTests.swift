import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import SlidePilotCore
import Testing
@testable import SlidePilotRendering

/// Prototype measurements for issue #11. Timings are printed, not asserted.
@Suite struct DrawingPrototypeTests {
    // MARK: Page geometry

    @Test(arguments: [0, 90, 180, 270])
    func cornersMapToTheDisplayedCorners(rotation: Int) {
        let box = CGRect(x: 10, y: 20, width: 400, height: 300)
        let topLeft = PageGeometry.pagePoint(RelativePoint(x: 0, y: 0), box: box, rotation: rotation)
        let expected: CGPoint = switch rotation {
        case 90: CGPoint(x: box.minX, y: box.minY)
        case 180: CGPoint(x: box.maxX, y: box.minY)
        case 270: CGPoint(x: box.maxX, y: box.maxY)
        default: CGPoint(x: box.minX, y: box.maxY)
        }
        #expect(topLeft == expected)
    }

    // MARK: PencilKit bridge

    private static func syntheticDrawing(strokes: Int, pointsPerStroke: Int) -> PageDrawing {
        var drawing = PageDrawing()
        for s in 0..<strokes {
            let points = (0..<pointsPerStroke).map { i in
                let t = Double(i) / Double(pointsPerStroke - 1)
                return RelativePoint(x: 0.1 + 0.8 * t, y: 0.1 + 0.8 * Double(s) / Double(max(strokes, 2) - 1) + 0.02 * sin(t * 12))
            }
            drawing.strokes.append(DrawingStroke(color: StrokeColor.presets[s % 6], points: points))
        }
        return drawing
    }

    @Test(arguments: PageSection.allCases)
    func controlPointRoundTripKeepsPointsAndColors(section: PageSection) {
        let mapping = CanvasMapping(section: section.rect, canvasWidth: 1024, canvasHeight: 768)
        let model = Self.syntheticDrawing(strokes: 6, pointsPerStroke: 50)
        let pk = PencilKitBridge.pkDrawing(from: model, mapping: mapping)
        let back = PencilKitBridge.strokes(from: pk, mapping: mapping, sampling: .controlPoints)
        #expect(back.count == model.strokes.count)
        var maxError = 0.0
        for (a, b) in zip(model.strokes, back) {
            #expect(a.points.count == b.points.count)
            for (p, q) in zip(a.points, b.points) {
                maxError = max(maxError, abs(p.x - q.x), abs(p.y - q.y))
            }
            #expect(abs(a.color.red - b.color.red) < 0.01)
            #expect(abs(a.color.green - b.color.green) < 0.01)
            #expect(abs(a.color.blue - b.color.blue) < 0.01)
        }
        print("PROBE roundtrip section=\(section) maxRelativeError=\(maxError)")
        #expect(maxError < 1e-4)
    }

    @Test func strokeDrawnInPresenterSizeMirrorsToPresentationSize() {
        // A stroke made on a 640 × 480 PencilKit canvas showing the left half…
        let presenter = CanvasMapping(section: PageSection.left.rect, canvasWidth: 640, canvasHeight: 480)
        let model = PageDrawing(strokes: [DrawingStroke(color: .blue, points: [presenter.relative(x: 320, y: 240)])])
        let pk = PencilKitBridge.pkDrawing(from: model, mapping: presenter)
        let relative = PencilKitBridge.strokes(from: pk, mapping: presenter)
        // …lands in the middle of a 1920 × 1440 presentation view.
        let presentation = CanvasMapping(section: PageSection.left.rect, canvasWidth: 1920, canvasHeight: 1440)
        let p = presentation.canvas(relative[0].points[0])
        #expect(abs(p.x - 960) < 0.01 && abs(p.y - 720) < 0.01)
        #expect(abs(relative[0].points[0].x - 0.25) < 1e-6)
    }

    @Test func interpolatedSamplingAddsPoints() {
        let mapping = CanvasMapping(section: .fullPage, canvasWidth: 1024, canvasHeight: 768)
        let model = Self.syntheticDrawing(strokes: 1, pointsPerStroke: 20)
        let pk = PencilKitBridge.pkDrawing(from: model, mapping: mapping)
        let dense = PencilKitBridge.strokes(from: pk, mapping: mapping, sampling: .interpolated(spacing: 2))
        print("PROBE interpolated control=20 interpolated=\(dense[0].points.count)")
        #expect(dense[0].points.count > 20)
    }

    @Test func conversionCost() {
        let mapping = CanvasMapping(section: .fullPage, canvasWidth: 1366, canvasHeight: 1024)
        let model = Self.syntheticDrawing(strokes: 200, pointsPerStroke: 150)
        let clock = ContinuousClock()
        var pk = PKDrawing()
        let toPK = clock.measure { pk = PencilKitBridge.pkDrawing(from: model, mapping: mapping) }
        var back: [DrawingStroke] = []
        let fromPK = clock.measure { back = PencilKitBridge.strokes(from: pk, mapping: mapping) }
        let data = (try? JSONEncoder().encode(model)) ?? Data()
        let pkData = pk.dataRepresentation()
        print("PROBE conversion strokes=200 points=30000 toPK=\(toPK) fromPK=\(fromPK) json=\(data.count)B pkData=\(pkData.count)B")
        #expect(back.count == 200)
    }

    // MARK: Rendering

    @Test func rendererDrawsStrokesAndBackground() throws {
        let width = 200, height = 100
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Top-left origin like SwiftUI's Canvas.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let drawing = PageDrawing(
            strokes: [DrawingStroke(color: .black, points: [RelativePoint(x: 0, y: 0.5), RelativePoint(x: 1, y: 0.5)])],
            background: .white)
        let mapping = CanvasMapping(section: .fullPage, canvasWidth: Double(width), canvasHeight: Double(height))
        let clock = ContinuousClock()
        let duration = clock.measure { DrawingRenderer.draw(drawing, in: context, mapping: mapping, lineWidth: 4) }
        print("PROBE render 1 stroke=\(duration)")
        let image = try #require(context.makeImage())
        let pixels = try #require(image.dataProvider?.data as Data?)
        func pixel(_ x: Int, _ y: Int) -> UInt8 { pixels[y * image.bytesPerRow + x * 4] }
        #expect(pixel(100, 50) < 50)   // on the line: black
        #expect(pixel(100, 10) > 200)  // background: white
    }

    @Test func renderCostOfABusyPage() throws {
        let context = try #require(CGContext(
            data: nil, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let mapping = CanvasMapping(section: .fullPage, canvasWidth: 1920, canvasHeight: 1080)
        let drawing = Self.syntheticDrawing(strokes: 200, pointsPerStroke: 150)
        let duration = ContinuousClock().measure { DrawingRenderer.draw(drawing, in: context, mapping: mapping) }
        print("PROBE render strokes=200 points=30000 1920x1080=\(duration)")
    }

    // MARK: PDF export

    // PDFKit annotations log "dealloc from a background thread" when used off the main thread.
    @MainActor @Test(arguments: [0, 90])
    func exportWritesInkAnnotationsAtTheRightPlace(rotation: Int) throws {
        let source = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 400, height: 300), for: .mediaBox)
        page.rotation = rotation
        source.insert(page, at: 0)
        let drawing = PageDrawing(
            strokes: [DrawingStroke(color: .magenta, points: [RelativePoint(x: 0, y: 0), RelativePoint(x: 0.5, y: 0.5)])],
            background: .white)
        let exported = try #require(DrawingPDFExporter.export(source, drawings: [0: drawing]))
        let reloaded = try #require(exported.dataRepresentation().flatMap(PDFDocument.init(data:)))
        let annotations = try #require(reloaded.page(at: 0)?.annotations)
        let ink = try #require(annotations.first { $0.type == "Ink" })
        #expect(annotations.contains { $0.type == "Square" })
        #expect(ink.border.map { Double($0.lineWidth) } == PageDrawing.lineWidth)
        let paths = try #require(ink.paths)
        #expect(paths.count == 1)
        let bounds = paths[0].bounds
        // Diagonal from the displayed top-left corner to the page center.
        if rotation == 0 {
            #expect(abs(bounds.minX - 0) < 0.5 && abs(bounds.maxY - 300) < 0.5)
            #expect(abs(bounds.maxX - 200) < 0.5 && abs(bounds.minY - 150) < 0.5)
        } else {
            #expect(abs(bounds.minX - 0) < 0.5 && abs(bounds.minY - 0) < 0.5)
            #expect(abs(bounds.maxX - 200) < 0.5 && abs(bounds.maxY - 150) < 0.5)
        }
    }
}
