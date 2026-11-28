import Foundation
import Observation
import SlidePilotCore

/// Draw mode of one document (DRAW-01 to DRAW-08): the drawings in Core plus the state of
/// the drawing controls.
///
/// The undo history lives per page in `DocumentDrawings` (ADR 0016). Every undo entry point
/// names the slide the presenter sees, so undo can never change another slide: the toolbar
/// buttons pass the current page, and the editable drawing layer gives the system a
/// `DrawingUndoManager` for the page it shows.
@Observable
final class DrawingModel {
    /// The drawings of all pages and the stroke in progress.
    let drawings = DocumentDrawings()

    /// Whether the color popover is shown; also opened by the Apple Pencil (DRAW-11).
    var isColorPaletteShown = false

    /// The point size PencilKit gives a monoline stroke of width 2, measured from the first
    /// drawn stroke. Kept here because rotating the iPad can recreate the canvas.
    @ObservationIgnored var pencilKitPointSize: Double?

    var isActive: Bool { drawings.isDrawing }

    // MARK: - Draw mode

    func start(onPage page: Int) {
        drawings.startDrawing(onPage: page)
    }

    /// Leaves draw mode; the undo history ends with it (DRAW-08).
    func stop(onPage page: Int) {
        isColorPaletteShown = false
        drawings.stopDrawing(onPage: page)
    }

    /// Deletes all drawings and their undo history, when "Save drawings" is turned off
    /// (DRAW-06).
    func deleteAll() {
        drawings.deleteAll()
    }

    // MARK: - Changes

    /// Adds the stroke in progress (Mac layer).
    func commitLiveStroke() {
        drawings.commitLiveStroke()
    }

    /// Takes the strokes reported by the iPad canvas after a stroke ends.
    func replaceStrokes(_ strokes: [DrawingStroke], onPage page: Int) {
        drawings.replaceStrokes(strokes, onPage: page)
    }

    /// Clear Drawings (DRAW-04).
    func clear(page: Int) {
        drawings.clear(page: page)
    }

    /// Transparent or white canvas (DRAW-04); clears the strokes.
    func setBackground(_ background: CanvasBackground, onPage page: Int) {
        drawings.setBackground(background, onPage: page)
    }

    // MARK: - Undo (DRAW-08)

    func canUndo(onPage page: Int) -> Bool {
        drawings.canUndo(onPage: page)
    }

    func canRedo(onPage page: Int) -> Bool {
        drawings.canRedo(onPage: page)
    }

    func undo(onPage page: Int) {
        drawings.undo(onPage: page)
    }

    func redo(onPage page: Int) {
        drawings.redo(onPage: page)
    }

    /// The name of the step Undo would take back on `page`, for "Undo Drawing" in the Edit
    /// menu; empty when there is none.
    func undoActionName(onPage page: Int) -> String {
        drawings.undoChange(onPage: page).map(Self.actionName) ?? ""
    }

    func redoActionName(onPage page: Int) -> String {
        drawings.redoChange(onPage: page).map(Self.actionName) ?? ""
    }

    private static func actionName(of change: DrawingChange) -> String {
        switch change {
        case .stroke: String(localized: "Drawing")
        case .clear: String(localized: "Clear Drawings")
        case .background: String(localized: "Canvas Background")
        }
    }
}
