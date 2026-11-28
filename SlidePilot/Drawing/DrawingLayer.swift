import SlidePilotCore
import SlidePilotRendering
import SwiftUI

extension View {
    /// The drawing of `page`, read-only, over a slide surface (DRAW-01): presentation, current
    /// slide outside draw mode, next-slide preview and thumbnails. Apply it to the
    /// `SlideSurface` itself, so it has the slide's frame. Later layers (e.g. the pointer)
    /// stack as further overlays on top. `isOutlined` keeps the slide's hairline visible over
    /// a white canvas; the presentation has none.
    func drawingOverlay(
        _ drawings: DocumentDrawings, page: Int, region: PageRegion = .full, isOutlined: Bool = true
    ) -> some View {
        overlay {
            ReadOnlyDrawingLayer(drawings: drawings, page: page, region: region)
                .slideOutline(isOutlined && drawings.drawing(onPage: page).background == .white)
        }
    }
}

/// Shows the stored drawing and the stroke in progress, so the audience sees a line while it
/// is drawn. Never takes clicks or touches, so links below keep working.
private struct ReadOnlyDrawingLayer: View {
    let drawings: DocumentDrawings
    let page: Int
    let region: PageRegion

    var body: some View {
        let drawing = drawings.drawing(onPage: page)
        let live = drawings.liveStroke.flatMap { $0.page == page ? $0.stroke : nil }
        if !drawing.isEmpty || live != nil {
            DrawingCanvas(drawing: drawing, liveStroke: live, section: region.drawingSection)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Renders a page's drawing with Core Graphics, like every read-only view and the export
/// (ADR 0016). Part of the drawing layer, one of the custom-drawn surfaces of ADR 0010.
struct DrawingCanvas: View {
    let drawing: PageDrawing
    var liveStroke: DrawingStroke?
    var section: RelativeRect = .fullPage

    var body: some View {
        Canvas { context, size in
            let mapping = CanvasMapping(section: section, canvasWidth: size.width, canvasHeight: size.height)
            context.withCGContext { cgContext in
                DrawingRenderer.draw(drawing, liveStroke: liveStroke, in: cgContext, mapping: mapping)
            }
        }
    }
}

/// The editable drawing of the presenter's current slide in draw mode (DRAW-01): the Mac
/// layer for mouse and trackpad, PencilKit on iPad (ADR 0016).
struct EditableDrawingLayer: View {
    let model: DrawingModel
    let page: Int
    var region: PageRegion = .full
    /// Esc while the canvas has the keyboard leaves draw mode (DRAW-01). The canvas gets
    /// the key before SwiftUI's key handlers do.
    var onEscape: () -> Void = {}

    var body: some View {
        Group {
            #if os(macOS)
            MacDrawingLayer(model: model, page: page, section: region.drawingSection, onEscape: onEscape)
            #else
            PencilDrawingLayer(model: model, page: page, section: region.drawingSection, onEscape: onEscape)
            #endif
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Drawing Canvas"))
        .accessibilityHint(Text("Draw on the current slide"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

#if os(macOS)
/// Mouse and trackpad drawing on the Mac (ADR 0016). Each drag is one stroke; the stroke is
/// shown live on the presentation while it is drawn, like in the old app.
private struct MacDrawingLayer: View {
    let model: DrawingModel
    let page: Int
    let section: RelativeRect
    let onEscape: () -> Void

    var body: some View {
        let drawings = model.drawings
        let live = drawings.liveStroke.flatMap { $0.page == page ? $0.stroke : nil }
        DrawingCanvas(drawing: drawings.drawing(onPage: page), liveStroke: live, section: section)
            .overlay {
                MacDrawingInput(model: model, page: page, section: section, onEscape: onEscape)
            }
    }
}

/// Takes the mouse and, as first responder in draw mode, gives the Edit menu the drawing's
/// undo manager (DRAW-08). AppKit only for that: a SwiftUI view cannot provide one.
private struct MacDrawingInput: NSViewRepresentable {
    let model: DrawingModel
    let page: Int
    let section: RelativeRect
    let onEscape: () -> Void

    func makeNSView(context: Context) -> DrawingInputView {
        DrawingInputView(model: model)
    }

    func updateNSView(_ view: DrawingInputView, context: Context) {
        view.page = page
        view.section = section
        view.onEscape = onEscape
    }
}

private final class DrawingInputView: NSView, PassesSlideKeysToWindow {
    let model: DrawingModel
    var page = 0
    var section = RelativeRect.fullPage
    var onEscape: () -> Void = {}

    init(model: DrawingModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { model.undoManager }

    // A click into an inactive window draws right away, like the old canvas.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // Edit ▸ Undo and Redo reach the first responder; the window itself would use the
    // document's undo manager.
    @objc func undo(_ sender: Any?) {
        model.undoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        model.undoManager.redo()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    override func keyDown(with event: NSEvent) {
        // Esc only; `WindowKeyboardAnchor` takes the slide keys and "." before they get here.
        if event.keyCode == 53 {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = relativePoint(of: event) else { return }
        model.drawings.beginLiveStroke(onPage: page, at: [point])
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = relativePoint(of: event) else { return }
        model.drawings.extendLiveStroke(with: [point])
    }

    override func mouseUp(with event: NSEvent) {
        model.commitLiveStroke()
    }

    private func relativePoint(of event: NSEvent) -> RelativePoint? {
        let mapping = CanvasMapping(section: section, canvasWidth: bounds.width, canvasHeight: bounds.height)
        guard mapping.isValid else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        return mapping.relative(x: location.x, y: location.y)
    }
}

extension DrawingInputView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let undoManager = model.undoManager
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = undoManager.undoMenuItemTitle
            return undoManager.canUndo
        case #selector(redo(_:)):
            menuItem.title = undoManager.redoMenuItemTitle
            return undoManager.canRedo
        default:
            return true
        }
    }
}
#endif
