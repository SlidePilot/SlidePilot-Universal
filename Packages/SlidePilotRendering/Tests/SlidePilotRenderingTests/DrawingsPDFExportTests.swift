import CoreGraphics
import Foundation
import PDFKit
import SlidePilotCore
import Testing
@testable import SlidePilotRendering

@Suite struct DrawingsPDFExportTests {
    private let line = DrawingStroke(
        color: .blue,
        points: [RelativePoint(x: 0.1, y: 0.5), RelativePoint(x: 0.5, y: 0.5), RelativePoint(x: 0.9, y: 0.6)]
    )

    private func reopen(_ data: Data) throws -> PDFDocument {
        try #require(PDFDocument(data: data))
    }

    private func render(_ data: Data, page: Int = 0) async throws -> CGImage {
        try await SlideRasterizer(data: data)
            .render(page: page, region: .full, fitting: PixelSize(width: 400, height: 400)).image
    }

    // MARK: - Annotations

    @Test func everyStrokeBecomesOneInkAnnotationWithTheScreenLineWidth() throws {
        let pdf = TestPDF.make(pages: 2)
        let drawing = PageDrawing(strokes: [line, DrawingStroke(color: .orange, points: [RelativePoint(x: 0.2, y: 0.2)])])
        let document = try reopen(try DrawingsPDFExporter.export(pdf: pdf, drawings: [1: drawing]))

        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.annotations.isEmpty == true)
        let annotations = try #require(document.page(at: 1)?.annotations)
        #expect(annotations.count == 2)
        for annotation in annotations {
            #expect(annotation.type == "Ink")
            // DEF-05: the old app exported 1 pt instead of the 2 pt shown on screen.
            #expect(annotation.border?.lineWidth == 2)
        }
    }

    @Test func inkPathsLieWhereTheStrokeWasDrawn() throws {
        let pdf = TestPDF.make(pages: 1)
        let document = try reopen(try DrawingsPDFExporter.export(pdf: pdf, drawings: [0: PageDrawing(strokes: [line])]))
        let annotation = try #require(document.page(at: 0)?.annotations.first)
        let path = try #require(annotation.paths?.first)
        let size = TestPDF.pageSize
        let bounds = path.bounds.offsetBy(dx: annotation.bounds.minX, dy: annotation.bounds.minY)
        #expect(abs(bounds.minX - 0.1 * size.width) < 1)
        #expect(abs(bounds.maxX - 0.9 * size.width) < 1)
        // Relative y grows downwards, page y upwards.
        #expect(abs(bounds.maxY - 0.5 * size.height) < 1)
        #expect(abs(bounds.minY - 0.4 * size.height) < 1)
    }

    @Test func drawingsOfPagesThePDFDoesNotHaveAreIgnored() throws {
        let pdf = TestPDF.make(pages: 1)
        let document = try reopen(try DrawingsPDFExporter.export(pdf: pdf, drawings: [5: PageDrawing(strokes: [line])]))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.annotations.isEmpty == true)
    }

    @Test func emptyDrawingsLeaveACopyWithoutAnnotations() throws {
        let pdf = TestPDF.make(pages: 3)
        let document = try reopen(try DrawingsPDFExporter.export(pdf: pdf, drawings: [0: PageDrawing()]))
        #expect(document.pageCount == 3)
        for index in 0..<3 {
            #expect(document.page(at: index)?.annotations.isEmpty == true)
        }
    }

    @Test func cropBoxIsResetToTheMediaBox() throws {
        let source = try reopen(TestPDF.make(pages: 1))
        let page = try #require(source.page(at: 0))
        page.setBounds(CGRect(x: 20, y: 20, width: 100, height: 100), for: .cropBox)
        let pdf = try #require(source.dataRepresentation())

        let document = try reopen(try DrawingsPDFExporter.export(pdf: pdf, drawings: [:]))
        let exported = try #require(document.page(at: 0))
        #expect(exported.bounds(for: .cropBox) == exported.bounds(for: .mediaBox))
    }

    @Test func unreadableDataThrows() {
        #expect(throws: DrawingsPDFExportError.unreadablePDF) {
            try DrawingsPDFExporter.export(pdf: Data("no pdf".utf8), drawings: [:])
        }
    }

    @Test func lockedPDFThrows() {
        let pdf = TestPDF.make(pages: 1, userPassword: "secret")
        #expect(throws: DrawingsPDFExportError.unreadablePDF) {
            try DrawingsPDFExporter.export(pdf: pdf, drawings: [0: PageDrawing(strokes: [line])])
        }
    }

    // MARK: - White canvas (DEF-05)

    @Test func whiteCanvasIsExportedBelowTheStrokes() async throws {
        let pdf = TestPDF.make(pages: 1)
        let drawing = PageDrawing(strokes: [line], background: .white)
        let data = try DrawingsPDFExporter.export(pdf: pdf, drawings: [0: drawing])
        let annotations = try #require(try reopen(data).page(at: 0)?.annotations)
        #expect(annotations.map(\.type) == ["Square", "Ink"])

        let image = try await render(data)
        // The red left half and the blue right half are covered.
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.25, y: 0.2)) == .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.75, y: 0.8)) == .white)
    }

    @Test func whiteCanvasCoversOnlyTheCanvasSection() async throws {
        let pdf = TestPDF.make(pages: 1)
        let data = try DrawingsPDFExporter.export(
            pdf: pdf,
            drawings: [0: PageDrawing(background: .white)],
            section: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)
        )
        let image = try await render(data)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.25, y: 0.5)) == .red)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.75, y: 0.5)) == .white)
    }

    /// The top-left quarter of the displayed page turns white, whatever the page's rotation.
    @Test(arguments: [0, 90, 180, 270])
    func rotatedPagesUseTheDisplayedOrientation(rotation: Int) async throws {
        let pdf = try TestPDF.rotating(TestPDF.make(pages: 1), by: [rotation])
        let data = try DrawingsPDFExporter.export(
            pdf: pdf,
            drawings: [0: PageDrawing(background: .white)],
            section: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5)
        )
        let image = try await render(data)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.2, y: 0.2)) == .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.8, y: 0.8)) != .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.8, y: 0.2)) != .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.2, y: 0.8)) != .white)
    }

    @Test func mediaBoxWithAnOffsetOriginIsHonored() async throws {
        let source = try reopen(TestPDF.make(pages: 1))
        let page = try #require(source.page(at: 0))
        let size = TestPDF.pageSize
        page.setBounds(CGRect(x: 40, y: 30, width: size.width - 40, height: size.height - 30), for: .mediaBox)
        let pdf = try #require(source.dataRepresentation())

        let data = try DrawingsPDFExporter.export(
            pdf: pdf,
            drawings: [0: PageDrawing(strokes: [line], background: .white)],
            section: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5)
        )
        let image = try await render(data)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.2, y: 0.2)) == .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.8, y: 0.8)) != .white)
    }

    /// Checked on the rendered page: how PDFKit reads ink paths back differs between OS versions
    /// when the media box does not start at zero.
    @Test func strokesOnAnOffsetMediaBoxAreDrawnWhereTheyWereDrawn() async throws {
        let source = try reopen(TestPDF.make(pages: 1))
        let page = try #require(source.page(at: 0))
        let size = TestPDF.pageSize
        page.setBounds(CGRect(x: 40, y: 30, width: size.width - 40, height: size.height - 30), for: .mediaBox)
        let pdf = try #require(source.dataRepresentation())
        let stroke = DrawingStroke(
            color: .black,
            points: [RelativePoint(x: 0.1, y: 0.5), RelativePoint(x: 0.9, y: 0.5)]
        )

        let data = try DrawingsPDFExporter.export(pdf: pdf, drawings: [0: PageDrawing(strokes: [stroke], background: .white)])
        let image = try await SlideRasterizer(data: data)
            .render(page: 0, region: .full, fitting: PixelSize(width: 1600, height: 1600)).image
        // A stroke shifted by the media box origin (12 % of the page) would miss these points.
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.5, y: 0.5)) == .other)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.85, y: 0.5)) == .other)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.5, y: 0.45)) == .white)
        #expect(PixelProbe.color(of: image, atUnit: CGPoint(x: 0.5, y: 0.55)) == .white)
    }

    // MARK: - Mapping

    @Test func mappingUndoesTheRotation() {
        let box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let topLeft = RelativePoint(x: 0, y: 0)
        // The displayed top-left corner is the page's top-left corner turned by /Rotate.
        #expect(ExportMapping(mediaBox: box, rotation: 0).pagePoint(topLeft) == CGPoint(x: 0, y: 300))
        #expect(ExportMapping(mediaBox: box, rotation: 90).pagePoint(topLeft) == CGPoint(x: 0, y: 0))
        #expect(ExportMapping(mediaBox: box, rotation: 180).pagePoint(topLeft) == CGPoint(x: 400, y: 0))
        #expect(ExportMapping(mediaBox: box, rotation: 270).pagePoint(topLeft) == CGPoint(x: 400, y: 300))
        #expect(ExportMapping(mediaBox: box, rotation: -90).pagePoint(topLeft) == CGPoint(x: 400, y: 300))
    }

    // MARK: - File name

    @Test func exportNameAppendsTheLocalizedSuffix() {
        #expect(DrawingsPDFExporter.exportName(forPDFBaseName: "talk", localizedDrawings: "Zeichnungen") == "talk-Zeichnungen.pdf")
        #expect(DrawingsPDFExporter.exportName(forPDFBaseName: nil, localizedDrawings: "Drawings") == "Drawings.pdf")
        #expect(DrawingsPDFExporter.exportName(forPDFBaseName: "", localizedDrawings: "Drawings") == "Drawings.pdf")
    }
}
