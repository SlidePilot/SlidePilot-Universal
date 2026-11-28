import Foundation

/// The undo manager the editable drawing layer hands to the system as first responder in
/// draw mode: Edit ▸ Undo and Redo, ⌘Z / ⇧⌘Z and the iPad undo gestures (DRAW-08).
///
/// It keeps no actions of its own. Everything is answered from the history of `page`, the
/// slide the layer shows, in `DocumentDrawings`. One stack of registered actions for the
/// whole document would undo strokes on slides the presenter does not see once slides
/// change in draw mode ("Save drawings", #238). It is also not the document's undo manager:
/// drawings are not part of the PDF, so drawing must not mark it edited.
final class DrawingUndoManager: UndoManager {
    private let model: DrawingModel
    /// The slide the drawing layer shows; the layer keeps it current.
    var page = 0

    init(model: DrawingModel) {
        self.model = model
        super.init()
    }

    override var canUndo: Bool { model.canUndo(onPage: page) }
    override var canRedo: Bool { model.canRedo(onPage: page) }

    override func undo() {
        model.undo(onPage: page)
    }

    override func redo() {
        model.redo(onPage: page)
    }

    override var undoActionName: String { model.undoActionName(onPage: page) }
    override var redoActionName: String { model.redoActionName(onPage: page) }

    // The system's titles ("Undo Drawing"), localized by Foundation.
    override var undoMenuItemTitle: String { undoMenuTitle(forUndoActionName: undoActionName) }
    override var redoMenuItemTitle: String { redoMenuTitle(forUndoActionName: redoActionName) }
}
