#if os(iOS)
import PencilKit
import SlidePilotCore
import SlidePilotRendering
import SwiftUI
import UIKit

/// Apple Pencil and finger drawing on iPad: `PKCanvasView` as the input layer on top of the
/// model (ADR 0016). The model stays the source of truth; the canvas is rebuilt from it after
/// undo, clear, a background change or a new size.
struct PencilDrawingLayer: View {
    let model: DrawingModel
    let page: Int
    let section: RelativeRect
    let onEscape: () -> Void

    var body: some View {
        // The canvas is transparent; a white canvas is drawn below it (DRAW-04).
        let background = model.drawings.drawing(onPage: page).background
        DrawingCanvas(drawing: PageDrawing(background: background), section: section)
            .overlay {
                GeometryReader { proxy in
                    PencilCanvas(
                        model: model,
                        page: page,
                        mapping: CanvasMapping(section: section, canvasWidth: proxy.size.width, canvasHeight: proxy.size.height),
                        color: model.drawings.color,
                        drawing: model.drawings.drawing(onPage: page),
                        onEscape: onEscape
                    )
                }
            }
    }
}

private struct PencilCanvas: UIViewRepresentable {
    let model: DrawingModel
    let page: Int
    let mapping: CanvasMapping
    let color: StrokeColor
    /// Passed in so a change of the model updates the canvas.
    let drawing: PageDrawing
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> DrawingInputContainer {
        let canvas = UndoFreeCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        // PencilKit adapts ink to dark mode (black would show as white); slides are light.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator

        // PencilKit reports a stroke only when it ends, and with a finger its gesture starts
        // only after a clear movement. This tracker follows the touch from the first contact,
        // so the presentation shows the stroke while it is drawn (ADR 0016).
        let tracker = TouchTracker()
        tracker.delegate = context.coordinator
        tracker.onTouches = { [weak coordinator = context.coordinator] phase, points, isPencil in
            coordinator?.followTouches(phase, points, isPencil: isPencil)
        }
        canvas.addGestureRecognizer(tracker)

        // Apple Pencil double-tap and squeeze (DRAW-11).
        let pencil = UIPencilInteraction(delegate: context.coordinator)
        canvas.addInteraction(pencil)
        return DrawingInputContainer(canvas: canvas, undoManager: model.undoManager)
    }

    func updateUIView(_ container: DrawingInputContainer, context: Context) {
        let canvas = container.canvas
        let coordinator = context.coordinator
        container.onEscape = onEscape
        // Follows the system's "Only Draw with Apple Pencil" setting. `.default` would follow
        // a tool picker, which this canvas does not have (ADR 0016).
        canvas.drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing ? .pencilOnly : .anyInput
        coordinator.page = page
        coordinator.mapping = mapping
        if coordinator.color != color {
            coordinator.color = color
            canvas.tool = PKInkingTool(.monoline, color: PencilKitBridge.platformColor(color), width: PageDrawing.lineWidth)
        }
        if drawing != coordinator.synced || mapping != coordinator.syncedMapping || page != coordinator.syncedPage {
            coordinator.rebuild(canvas, from: drawing)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        let model: DrawingModel
        var page = 0
        var mapping = CanvasMapping(canvasWidth: 0, canvasHeight: 0)
        var color: StrokeColor?
        /// The model's drawing that the canvas shows.
        var synced: PageDrawing?
        var syncedMapping: CanvasMapping?
        var syncedPage: Int?
        /// The number of PencilKit strokes that are already in the model.
        private var syncedStrokeCount = 0
        private var isApplying = false
        private var liveGeneration = 0
        /// Whether the tracked touch draws; a rejected finger's moves are ignored.
        private var isFollowing = false

        init(model: DrawingModel) {
            self.model = model
        }

        func rebuild(_ canvas: PKCanvasView, from drawing: PageDrawing) {
            let pointSize = model.pencilKitPointSize ?? PencilKitBridge.defaultPointSize
            isApplying = true
            canvas.drawing = PencilKitBridge.pkDrawing(from: drawing, mapping: mapping, pointSize: pointSize)
            isApplying = false
            synced = drawing
            syncedMapping = mapping
            syncedPage = page
            syncedStrokeCount = canvas.drawing.strokes.count
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying else { return }
            let pkStrokes = canvasView.drawing.strokes
            guard pkStrokes.count > syncedStrokeCount else {
                // Not a new stroke (PencilKit has no eraser here): show the model again,
                // unless the canvas already shows it.
                let drawing = model.drawings.drawing(onPage: page)
                if pkStrokes.count != syncedStrokeCount || drawing != synced {
                    rebuild(canvasView, from: drawing)
                }
                return
            }
            let added = Array(pkStrokes[syncedStrokeCount...])
            if model.pencilKitPointSize == nil, let size = added.last?.path.first?.size, size.width > 0 {
                model.pencilKitPointSize = size.width
            }
            // Only the new strokes are converted; sampling the older ones again would let
            // them drift a little with every stroke.
            let newStrokes = PencilKitBridge.strokes(from: PKDrawing(strokes: added), mapping: mapping)
            let strokes = model.drawings.drawing(onPage: page).strokes + newStrokes
            model.replaceStrokes(strokes, onPage: page)
            synced = model.drawings.drawing(onPage: page)
            syncedStrokeCount = pkStrokes.count
        }

        // MARK: Live mirror

        func followTouches(_ phase: TouchTracker.Phase, _ locations: [CGPoint], isPencil: Bool) {
            guard mapping.isValid else { return }
            let points = locations.map { mapping.relative(x: $0.x, y: $0.y) }
            let drawings = model.drawings
            switch phase {
            case .began:
                // Fingers do not draw when the system setting says Apple Pencil only.
                guard isPencil || !UIPencilInteraction.prefersPencilOnlyDrawing else { return }
                isFollowing = true
                liveGeneration += 1
                drawings.beginLiveStroke(onPage: page, at: points)
            case .moved:
                guard isFollowing else { return }
                drawings.extendLiveStroke(with: points)
            case .ended:
                guard isFollowing else { return }
                isFollowing = false
                // The stroke stays until PencilKit reports it, so the mirror never flashes
                // empty; dropped if PencilKit adds no stroke.
                let generation = liveGeneration
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.liveGeneration == generation else { return }
                    if self.model.drawings.liveStroke?.page == self.page {
                        self.model.drawings.cancelLiveStroke()
                    }
                }
            case .cancelled:
                guard isFollowing else { return }
                isFollowing = false
                drawings.cancelLiveStroke()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: Apple Pencil (DRAW-11)

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            perform(UIPencilInteraction.preferredTapAction)
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else { return }
            perform(UIPencilInteraction.preferredSqueezeAction)
        }

        private func perform(_ action: UIPencilPreferredAction) {
            switch action {
            case .switchPrevious:
                model.drawings.switchToPreviousColor()
            case .showColorPalette, .showInkAttributes, .showContextualPalette:
                model.isColorPaletteShown = true
            default:
                // Off, the eraser (there is none) and system shortcuts: nothing to do here.
                break
            }
        }
    }
}

/// Holds the canvas and, as first responder in draw mode, gives ⌘Z, the Edit menu and the
/// undo gestures the drawing's undo manager (DRAW-08).
final class DrawingInputContainer: UIView {
    let canvas: PKCanvasView
    var onEscape: () -> Void = {}
    private let drawingUndoManager: UndoManager

    init(canvas: PKCanvasView, undoManager: UndoManager) {
        self.canvas = canvas
        drawingUndoManager = undoManager
        super.init(frame: .zero)
        canvas.frame = bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { drawingUndoManager }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }

    // Esc on a hardware keyboard leaves draw mode; other keys go on up the chain.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
            onEscape()
        } else {
            super.pressesBegan(presses, with: event)
        }
    }
}

/// A canvas that keeps PencilKit's own undo actions out of the drawing's undo manager. Undo
/// goes through the model, one history per page (DRAW-08, ADR 0016).
private final class UndoFreeCanvasView: PKCanvasView {
    private let ownUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownUndoManager }
}

/// Observes the touches of one stroke from the first contact on and never recognizes, so it
/// does not interfere with PencilKit's own gestures. A second finger cancels the stroke,
/// because PencilKit does not draw then.
final class TouchTracker: UIGestureRecognizer {
    enum Phase { case began, moved, ended, cancelled }

    var onTouches: ((Phase, [CGPoint], Bool) -> Void)?
    private var tracked: UITouch?

    override init(target: Any? = nil, action: Selector? = nil) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if tracked != nil || (event.allTouches?.count ?? 0) > 1 {
            finish(.cancelled)
            return
        }
        guard let touch = touches.first else { return }
        tracked = touch
        onTouches?(.began, locations(of: touch, event), touch.type == .pencil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        onTouches?(.moved, locations(of: tracked, event), tracked.type == .pencil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(.cancelled)
    }

    override func reset() {
        tracked = nil
    }

    private func finish(_ phase: Phase) {
        if let tracked {
            onTouches?(phase, [], tracked.type == .pencil)
        }
        tracked = nil
        state = .failed
    }

    private func locations(of touch: UITouch, _ event: UIEvent) -> [CGPoint] {
        (event.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: view) }
    }
}
#endif
