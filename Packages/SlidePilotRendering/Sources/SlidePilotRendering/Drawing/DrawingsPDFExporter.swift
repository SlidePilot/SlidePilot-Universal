import CoreGraphics
import Foundation
import PDFKit
import SlidePilotCore

#if canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformBezierPath = NSBezierPath
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformBezierPath = UIBezierPath
#endif

public enum DrawingsPDFExportError: Error, Sendable, Equatable {
    /// The PDF could not be opened or is locked.
    case unreadablePDF
    /// PDFKit could not write the copy.
    case writeFailed
}

/// Writes a copy of a PDF with the drawings as annotations (DRAW-10).
///
/// Like the old app, every stroke becomes one ink annotation, so the drawings stay editable
/// in other PDF apps, and the crop box of every page is reset to its media box (the app shows
/// the media box). Unlike the old app (DEF-05), a white canvas is exported as a white square
/// annotation below the strokes, and strokes keep the line width they have on screen.
public enum DrawingsPDFExporter {
    /// The copy of `pdf` with `drawings` (by page index) on its pages. Pages without a
    /// drawing and drawings of pages the PDF does not have are left out.
    ///
    /// `section` is the part of each page the canvas covered (split notes, DRAW-02); a white
    /// canvas covers only that part.
    public static func export(
        pdf: Data,
        drawings: [Int: PageDrawing],
        section: RelativeRect = .fullPage
    ) throws(DrawingsPDFExportError) -> Data {
        guard let document = PDFDocument(data: pdf), !document.isLocked else { throw .unreadablePDF }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)
            page.setBounds(mediaBox, for: .cropBox)
            guard let drawing = drawings[index], !drawing.isEmpty else { continue }
            let mapping = ExportMapping(mediaBox: mediaBox, rotation: page.rotation)
            if drawing.background == .white {
                page.addAnnotation(whiteCanvas(covering: mapping.pageRect(section)))
            }
            for stroke in drawing.strokes {
                if let annotation = ink(stroke, mapping: mapping) {
                    page.addAnnotation(annotation)
                }
            }
        }
        guard let data = document.dataRepresentation() else { throw .writeFailed }
        return data
    }

    /// The file name the export suggests: `<pdf>-<localized "Drawings">.pdf`, or
    /// `<localized "Drawings">.pdf` without a PDF name, like the old app.
    public static func exportName(forPDFBaseName baseName: String?, localizedDrawings: String) -> String {
        guard let baseName, !baseName.isEmpty else { return localizedDrawings + ".pdf" }
        return baseName + "-" + localizedDrawings + ".pdf"
    }

    private static func whiteCanvas(covering rect: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        let white = PlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
        annotation.color = white
        annotation.interiorColor = white
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.shouldPrint = true
        return annotation
    }

    private static func ink(_ stroke: DrawingStroke, mapping: ExportMapping) -> PDFAnnotation? {
        guard let first = stroke.points.first else { return nil }
        // Ink paths are relative to the annotation's origin; the annotation covers the page.
        let bounds = mapping.mediaBox
        let path = PlatformBezierPath()
        let start = mapping.pagePoint(first, relativeTo: bounds.origin)
        path.move(to: start)
        if stroke.points.count == 1 {
            // A tap is a dot, like on screen.
            path.addLineTo(start)
        }
        for point in stroke.points.dropFirst() {
            path.addLineTo(mapping.pagePoint(point, relativeTo: bounds.origin))
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = PlatformColor(
            red: stroke.color.red, green: stroke.color.green, blue: stroke.color.blue, alpha: stroke.color.alpha
        )
        let border = PDFBorder()
        border.lineWidth = PageDrawing.lineWidth
        annotation.border = border
        annotation.shouldPrint = true
        annotation.add(path)
        return annotation
    }
}

/// Maps relative points of the displayed page (top-left origin, `/Rotate` applied, DRAW-02)
/// to PDF page space (bottom-left origin of the unrotated media box).
struct ExportMapping {
    let mediaBox: CGRect
    let rotation: Int

    init(mediaBox: CGRect, rotation: Int) {
        self.mediaBox = mediaBox
        self.rotation = ((rotation % 360) + 360) % 360
    }

    /// `point` in page space.
    func pagePoint(_ point: RelativePoint) -> CGPoint {
        pagePoint(point, relativeTo: .zero)
    }

    /// `point` in page space, minus `origin`.
    func pagePoint(_ point: RelativePoint, relativeTo origin: CGPoint) -> CGPoint {
        let size = PageGeometry.displayedSize(mediaBox: mediaBox, rotation: rotation)
        // In the displayed page with a bottom-left origin.
        let dx = point.x * size.width
        let dy = (1 - point.y) * size.height
        let width = mediaBox.width
        let height = mediaBox.height
        // `/Rotate` turns the page clockwise for display; undo that turn.
        let unrotated = switch rotation {
        case 90: CGPoint(x: width - dy, y: dx)
        case 180: CGPoint(x: width - dx, y: height - dy)
        case 270: CGPoint(x: dy, y: height - dx)
        default: CGPoint(x: dx, y: dy)
        }
        return CGPoint(
            x: mediaBox.minX + unrotated.x - origin.x,
            y: mediaBox.minY + unrotated.y - origin.y
        )
    }

    /// `rect` (relative, displayed) in page space.
    func pageRect(_ rect: RelativeRect) -> CGRect {
        let a = pagePoint(RelativePoint(x: rect.x, y: rect.y))
        let b = pagePoint(RelativePoint(x: rect.x + rect.width, y: rect.y + rect.height))
        return CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        )
    }
}

private extension PlatformBezierPath {
    func addLineTo(_ point: CGPoint) {
        #if canImport(AppKit)
        line(to: point)
        #else
        addLine(to: point)
        #endif
    }
}
