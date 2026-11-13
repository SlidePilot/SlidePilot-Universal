import PDFKit
import SlidePilotCore
#if os(macOS)
import AppKit
private typealias PlatformBezierPath = NSBezierPath
private typealias PlatformColor = NSColor
#else
import UIKit
private typealias PlatformBezierPath = UIBezierPath
private typealias PlatformColor = UIColor
#endif

/// Exports drawings into a copy of the PDF as ink annotations (DRAW-10).
/// Prototype: works on the main actor because `PDFDocument` is not Sendable.
public enum DrawingPDFExporter {
    public static func export(
        _ document: PDFDocument,
        drawings: [Int: PageDrawing],
        lineWidth: Double = PageDrawing.lineWidth
    ) -> PDFDocument? {
        guard let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { return nil }
        for index in 0..<copy.pageCount {
            guard let page = copy.page(at: index) else { continue }
            let media = page.bounds(for: .mediaBox)
            // The old app resets the crop box, so relative points refer to the media box.
            page.setBounds(media, for: .cropBox)
            guard let drawing = drawings[index], !drawing.isEmpty else { continue }

            if drawing.background == .white {
                // The old app dropped the white background (DEF-05).
                let square = PDFAnnotation(bounds: media, forType: .square, withProperties: nil)
                square.color = .clear
                square.interiorColor = .white
                let border = PDFBorder()
                border.lineWidth = 0
                square.border = border
                page.addAnnotation(square)
            }
            for stroke in drawing.strokes where !stroke.points.isEmpty {
                let annotation = PDFAnnotation(bounds: media, forType: .ink, withProperties: nil)
                annotation.color = platformColor(stroke.color)
                let border = PDFBorder()
                border.lineWidth = lineWidth
                annotation.border = border
                let path = PlatformBezierPath()
                for (i, point) in stroke.points.enumerated() {
                    var p = PageGeometry.pagePoint(point, box: media, rotation: page.rotation)
                    // Ink paths are relative to the annotation's origin.
                    p.x -= media.minX
                    p.y -= media.minY
                    if i == 0 { path.move(to: p) } else { addLine(path, to: p) }
                }
                if stroke.points.count == 1 { addLine(path, to: path.currentPoint) }
                annotation.add(path)
                page.addAnnotation(annotation)
            }
        }
        return copy
    }

    private static func platformColor(_ color: StrokeColor) -> PlatformColor {
        PlatformColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func addLine(_ path: PlatformBezierPath, to point: CGPoint) {
        #if os(macOS)
        path.line(to: point)
        #else
        path.addLine(to: point)
        #endif
    }
}

