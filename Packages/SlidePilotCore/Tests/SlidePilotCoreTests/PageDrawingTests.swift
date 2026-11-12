import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct PageDrawingTests {
    @Test(arguments: PageSection.allCases)
    func canvasRoundTripIsExact(section: PageSection) {
        let mapping = CanvasMapping(section: section.rect, canvasWidth: 800, canvasHeight: 600)
        for (x, y) in [(0.0, 0.0), (800.0, 600.0), (123.4, 456.7), (400, 300)] {
            let back = mapping.canvas(mapping.relative(x: x, y: y))
            #expect(abs(back.x - x) < 1e-9)
            #expect(abs(back.y - y) < 1e-9)
        }
    }

    @Test func rightHalfMapsCanvasToRightHalfOfPage() {
        let mapping = CanvasMapping(section: PageSection.right.rect, canvasWidth: 400, canvasHeight: 300)
        #expect(mapping.relative(x: 0, y: 0) == RelativePoint(x: 0.5, y: 0))
        #expect(mapping.relative(x: 400, y: 300) == RelativePoint(x: 1, y: 1))
        #expect(mapping.relative(x: 200, y: 150) == RelativePoint(x: 0.75, y: 0.5))
    }

    @Test func sameRelativePointLandsOnSameSpotInDifferentlySizedViews() {
        // Presenter canvas and presentation window show the same section at different sizes.
        let presenter = CanvasMapping(section: PageSection.left.rect, canvasWidth: 640, canvasHeight: 480)
        let presentation = CanvasMapping(section: PageSection.left.rect, canvasWidth: 1920, canvasHeight: 1440)
        let point = presenter.relative(x: 320, y: 120)
        let mirrored = presentation.canvas(point)
        #expect(abs(mirrored.x - 960) < 1e-9)
        #expect(abs(mirrored.y - 360) < 1e-9)
    }

    @Test func backgroundChangeClearsStrokes() {
        var drawing = PageDrawing(strokes: [DrawingStroke(color: .blue, points: [RelativePoint(x: 0.1, y: 0.1)])])
        drawing.setBackground(.white)
        #expect(drawing.strokes.isEmpty)
        #expect(drawing.background == .white)
    }

    @Test func codableRoundTrip() throws {
        let drawing = PageDrawing(
            strokes: [DrawingStroke(color: .orange, points: [RelativePoint(x: 0.25, y: 0.75)])],
            background: .white)
        let data = try JSONEncoder().encode(drawing)
        #expect(try JSONDecoder().decode(PageDrawing.self, from: data) == drawing)
    }
}
