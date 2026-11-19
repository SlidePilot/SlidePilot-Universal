import Foundation
import Observation
import SlidePilotCore

/// Draw mode of one document (DRAW-01 to DRAW-08): the drawings in Core plus the window's
/// undo manager and the state of the drawing controls.
///
/// Every change made by the user goes through here, so it is registered with the system
/// `UndoManager` (Edit menu, ⌘Z, iPad undo gestures). The undo history itself lives per page
/// in `DocumentDrawings`; the undo manager only triggers it (ADR 0016).
@Observable
final class DrawingModel {
    /// The drawings of all pages and the stroke in progress.
    let drawings = DocumentDrawings()

    /// Whether the color popover is shown; also opened by the Apple Pencil (DRAW-11).
    var isColorPaletteShown = false

    /// The window's undo manager, set by the presenter. Weak: the window owns it.
    @ObservationIgnored weak var undoManager: UndoManager?

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
        undoManager?.removeAllActions(withTarget: self)
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

    /// Registers one step of `page`'s history. Undoing it registers the redo and the other
    /// way round, so the undo manager mirrors the page's history.
    private func registerUndo(onPage page: Int, name: String, isUndo: Bool = true) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            // Undo actions run on the main thread, where the window's undo manager lives.
            MainActor.assumeIsolated {
                model.step(onPage: page, name: name, isUndo: isUndo)
            }
        }
        undoManager.setActionName(name)
    }

    private func step(onPage page: Int, name: String, isUndo: Bool) {
        let didStep = isUndo ? drawings.undo(onPage: page) : drawings.redo(onPage: page)
        guard didStep else { return }
        registerUndo(onPage: page, name: name, isUndo: !isUndo)
    }
}
