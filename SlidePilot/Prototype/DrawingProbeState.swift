import CoreGraphics
import Foundation
import Observation
import PDFKit
import SlidePilotCore
import SlidePilotRendering

/// Prototype for issue #11 – not for main.
enum DrawingEngine: String, CaseIterable, Identifiable {
    case custom = "Custom layer"
    case pencilKit = "PencilKit"
    var id: String { rawValue }
}

@Observable @MainActor
final class DrawingProbeState {
    static let fixtures = ["notes-right", "rotated", "plain-slides"]

    var fixture = "notes-right" { didSet { load() } }
    private(set) var document: PDFDocument?
    var pageIndex = 0 { didSet { liveStroke = nil; bump() } }
    var section: PageSection = .left { didSet { bump() } }
    var engine: DrawingEngine = .custom { didSet { bump() } }
    var color: StrokeColor = .blue
    var pencilOnly = false
    var showsToolPicker = true
    var adaptsInkToDarkMode = false
    var interpolatedSampling = true
    var liveMirrorsPencilKit = true

    private(set) var drawings: [Int: PageDrawing] = [:]
    /// The stroke being drawn right now (custom layer only), mirrored live.
    var liveStroke: DrawingStroke?
    /// Changes whenever the model changes outside the PencilKit canvas, so the
    /// canvas rebuilds its `PKDrawing` from the model.
    private(set) var externalRevision = 0

    private var undoStack: [[Int: PageDrawing]] = []
    private var redoStack: [[Int: PageDrawing]] = []
    private(set) var log: [String] = []
    private var imageCache: [String: CGImage] = [:]

    init() { load() }

    var pageCount: Int { document?.pageCount ?? 0 }
    var currentDrawing: PageDrawing { drawings[pageIndex] ?? PageDrawing() }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The drawing including the stroke in progress, for read-only views.
    var displayedDrawing: PageDrawing {
        var drawing = currentDrawing
        if let liveStroke { drawing.strokes.append(liveStroke) }
        return drawing
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: fixture, withExtension: "pdf") else {
            record("Fixture \(fixture) missing")
            return
        }
        document = PDFDocument(url: url)
        drawings = [:]
        undoStack = []
        redoStack = []
        imageCache = [:]
        if pageIndex != 0 { pageIndex = 0 } else { bump() }
        section = fixture == "notes-right" ? .left : .full
        record("Loaded \(fixture): \(pageCount) pages")
    }

    private func bump() { externalRevision += 1 }

    // MARK: Editing

    private func mutate(bumpRevision: Bool = true, _ change: (inout PageDrawing) -> Void) {
        undoStack.append(drawings)
        redoStack.removeAll()
        var drawing = currentDrawing
        change(&drawing)
        drawings[pageIndex] = drawing
        if bumpRevision { bump() }
    }

    func addStroke(_ stroke: DrawingStroke) {
        mutate { $0.strokes.append(stroke) }
    }

    /// Called by the PencilKit canvas; the canvas already shows the change.
    func replaceStrokesFromCanvas(_ strokes: [DrawingStroke]) {
        mutate(bumpRevision: false) { $0.strokes = strokes }
    }

    func clear() { mutate { $0.clear() } }

    func setBackground(_ background: CanvasBackground) { mutate { $0.setBackground(background) } }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(drawings)
        drawings = previous
        bump()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(drawings)
        drawings = next
        bump()
    }

    // MARK: Page images

    /// Displayed page size (after rotation) in points.
    func displayedPageSize() -> CGSize {
        guard let page = document?.page(at: pageIndex) else { return CGSize(width: 4, height: 3) }
        let box = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    var sectionAspectRatio: CGFloat {
        let size = displayedPageSize()
        return size.width * section.rect.width / (size.height * section.rect.height)
    }

    /// Renders the shown section of the current page.
    func pageImage(pixelWidth: Int) -> CGImage? {
        let key = "\(fixture)-\(pageIndex)-\(section)-\(pixelWidth)"
        if let cached = imageCache[key] { return cached }
        guard pixelWidth > 0, let page = document?.page(at: pageIndex) else { return nil }
        let displayed = displayedPageSize()
        let rect = section.rect
        let scale = CGFloat(pixelWidth) / (displayed.width * rect.width)
        let pixelHeight = Int((displayed.height * rect.height * scale).rounded())
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: max(pixelHeight, 1), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        // Section origin is top-left; the context's origin is bottom-left.
        context.translateBy(x: -rect.x * displayed.width, y: -(1 - rect.y - rect.height) * displayed.height)
        page.draw(with: .cropBox, to: context)
        let image = context.makeImage()
        imageCache[key] = image
        return image
    }

    // MARK: Export and log

    func export() {
        guard let document else { return }
        let clock = ContinuousClock()
        var exported: PDFDocument?
        let duration = clock.measure { exported = DrawingPDFExporter.export(document, drawings: drawings) }
        let data = exported?.dataRepresentation()
        let ink = (0..<(exported?.pageCount ?? 0))
            .compactMap { exported?.page(at: $0)?.annotations.filter { $0.type == "Ink" }.count }
            .reduce(0, +)
        if let data {
            let url = FileManager.default.temporaryDirectory.appending(path: "drawing-export.pdf")
            try? data.write(to: url)
        }
        record("Export: \(ink) ink annotations, \(data?.count ?? 0) B, \(Self.format(duration))")
    }

    func record(_ line: String) {
        log.append(line)
        if log.count > 14 { log.removeFirst(log.count - 14) }
    }

    static func format(_ duration: Duration) -> String {
        let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
        return String(format: "%.2f ms", ms)
    }
}
