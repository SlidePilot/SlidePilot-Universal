import Foundation
import Observation
import SlidePilotCore

/// Draw mode of one document (DRAW-01 to DRAW-08): the drawings in Core plus the undo
/// manager and the state of the drawing controls.
///
/// Every change made by the user goes through here, so it is registered with `undoManager`.
/// The editable drawing layer is the first responder in draw mode and hands this manager to
/// the Edit menu, ⌘Z and the iPad undo gestures. It is not the document's undo manager:
/// drawings are not part of the PDF, so drawing must not mark it edited. The undo
/// history itself lives per page in `DocumentDrawings`; the undo manager only triggers it
/// (ADR 0016).
@Observable
final class DrawingModel {
    /// The drawings of all pages and the stroke in progress.
    let drawings = DocumentDrawings()

    /// Whether the color popover is shown; also opened by the Apple Pencil (DRAW-11).
    var isColorPaletteShown = false

    /// Drawing undo and redo (DRAW-08), apart from the document's undo manager.
    @ObservationIgnored let undoManager: UndoManager = {
        let manager = UndoManager()
        // Each change is its own group (see `registerUndo`). Grouping by event left a group
        // open when undo was chosen, and `undo()` throws on an open group.
        manager.groupsByEvent = false
        return manager
    }()

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
        undoManager.removeAllActions()
        historyRevision += 1
    }

    /// Deletes all drawings and their undo history, when "Save drawings" is turned off
    /// (DRAW-06).
    func deleteAll() {
        drawings.deleteAll()
        undoManager.removeAllActions()
        historyRevision += 1
    }

    // MARK: - Changes

    /// Adds the stroke in progress (Mac layer).
    func commitLiveStroke() {
        guard let page = drawings.commitLiveStroke() else { return }
        registerUndo(onPage: page, name: String(localized: "Drawing"))
    }

    /// Takes the strokes reported by the iPad canvas after a stroke ends.
    func replaceStrokes(_ strokes: [DrawingStroke], onPage page: Int) {
        guard drawings.replaceStrokes(strokes, onPage: page) else { return }
        registerUndo(onPage: page, name: String(localized: "Drawing"))
    }

    /// Clear Drawings (DRAW-04).
    func clear(page: Int) {
        guard drawings.clear(page: page) else { return }
        registerUndo(onPage: page, name: String(localized: "Clear Drawings"))
    }

    /// Transparent or white canvas (DRAW-04); clears the strokes.
    func setBackground(_ background: CanvasBackground, onPage page: Int) {
        guard drawings.setBackground(background, onPage: page) else { return }
        registerUndo(onPage: page, name: String(localized: "Canvas Background"))
    }

    // MARK: - Undo (DRAW-08)

    /// Changes with every step of the undo history: `UndoManager` is not observable, so the
    /// toolbar's Undo and Redo buttons read this to update.
    private var historyRevision = 0

    var canUndo: Bool {
        _ = historyRevision
        return undoManager.canUndo
    }

    var canRedo: Bool {
        _ = historyRevision
        return undoManager.canRedo
    }

    /// The toolbar's Undo button (iPad, iPhone): a keyboard is not always attached.
    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        historyRevision += 1
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        historyRevision += 1
    }

    /// Registers one step of `page`'s history. Undoing it registers the redo and the other
    /// way round, so the undo manager mirrors the page's history.
    private func registerUndo(onPage page: Int, name: String, isUndo: Bool = true) {
        // While undoing or redoing, the undo manager has a group open for the opposite step.
        let needsGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if needsGroup {
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.step(onPage: page, name: name, isUndo: isUndo)
        }
        undoManager.setActionName(name)
        if needsGroup {
            undoManager.endUndoGrouping()
        }
        historyRevision += 1
    }

    private func step(onPage page: Int, name: String, isUndo: Bool) {
        // Also reached through ⌘Z and the iPad undo gestures.
        historyRevision += 1
        let didStep = isUndo ? drawings.undo(onPage: page) : drawings.redo(onPage: page)
        guard didStep else { return }
        registerUndo(onPage: page, name: name, isUndo: !isUndo)
    }
}
