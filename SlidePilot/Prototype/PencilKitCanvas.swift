#if os(iOS)
import PencilKit
import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// `PKCanvasView` showing the current page's drawing. The relative model stays
/// the source of truth: the canvas is rebuilt from it whenever the model changes
/// elsewhere or the canvas size or section changes.
struct PencilKitCanvas: UIViewRepresentable {
    let state: DrawingProbeState
    let mapping: CanvasMapping

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        // PencilKit adapts ink colors to dark mode; slides are always light.
        canvas.overrideUserInterfaceStyle = state.adaptsInkToDarkMode ? .unspecified : .light
        canvas.delegate = context.coordinator
        // PencilKit reports a change only when a stroke ends, and with a
        // finger its drawing gesture begins only after a clear movement (to
        // tell drawing from scrolling). A passive touch tracker feeds the
        // mirror from the first contact on, so slow finger strokes show live.
        let tracker = TouchTracker()
        tracker.delegate = context.coordinator
        tracker.onTouches = { [weak coordinator = context.coordinator] phase, points, isPencil in
            coordinator?.followTouches(phase, points, isPencil: isPencil)
        }
        canvas.addGestureRecognizer(tracker)
        let picker = PKToolPicker(toolItems: [
            PKToolPickerInkingItem(type: .monoline, color: Self.uiColor(state.color), width: PageDrawing.lineWidth),
        ])
        picker.colorUserInterfaceStyle = state.adaptsInkToDarkMode ? .unspecified : .light
        picker.addObserver(canvas)
        picker.addObserver(context.coordinator)
        context.coordinator.toolPicker = picker
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.mapping = mapping
        canvas.drawingPolicy = state.pencilOnly ? .pencilOnly : .anyInput
        canvas.overrideUserInterfaceStyle = state.adaptsInkToDarkMode ? .unspecified : .light

        coordinator.toolPicker?.colorUserInterfaceStyle = state.adaptsInkToDarkMode ? .unspecified : .light

        if coordinator.appliedRevision != state.externalRevision || coordinator.appliedMapping != mapping {
            let drawing = state.currentDrawing
            var pk = PKDrawing()
            let width = state.pencilKitPointWidth
            let duration = ContinuousClock().measure {
                pk = PencilKitBridge.pkDrawing(from: drawing, mapping: mapping, lineWidth: width)
            }
            coordinator.isApplying = true
            canvas.drawing = pk
            coordinator.isApplying = false
            coordinator.appliedRevision = state.externalRevision
            coordinator.appliedMapping = mapping
            state.record("Model → PKDrawing: \(drawing.strokes.count) strokes, point size \(String(format: "%.2f", width)), \(DrawingProbeState.format(duration))")
        }

        if let picker = coordinator.toolPicker {
            if state.showsToolPicker {
                picker.setVisible(true, forFirstResponder: canvas)
                Task { @MainActor in canvas.becomeFirstResponder() }
            } else {
                picker.setVisible(false, forFirstResponder: canvas)
                canvas.tool = PKInkingTool(.monoline, color: Self.uiColor(state.color), width: PageDrawing.lineWidth)
            }
        }
    }

    static func uiColor(_ c: StrokeColor) -> UIColor {
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver, UIGestureRecognizerDelegate {
        let state: DrawingProbeState
        var toolPicker: PKToolPicker?
        private var liveGeneration = 0
        var mapping = CanvasMapping(section: .fullPage, canvasWidth: 1, canvasHeight: 1)
        var appliedRevision = -1
        var appliedMapping: CanvasMapping?
        var isApplying = false
        private var changeCallsDuringStroke = 0
        private var strokeStart: ContinuousClock.Instant?

        init(state: DrawingProbeState) { self.state = state }

        func followTouches(_ phase: TouchTracker.Phase, _ locations: [CGPoint], isPencil: Bool) {
            guard state.liveMirrorsPencilKit else { return }
            let points = locations.map { mapping.relative(x: $0.x, y: $0.y) }
            switch phase {
            case .began:
                // Fingers do not draw in "Pencil only" mode.
                guard isPencil || !state.pencilOnly else { return }
                liveGeneration += 1
                state.liveStroke = DrawingStroke(color: state.color, points: points)
            case .moved:
                state.liveStroke?.points += points
            case .ended:
                // Cleared by the model update that follows, to avoid a flash.
                // Fallback in case PencilKit adds no stroke (nothing to update).
                let generation = liveGeneration
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.liveGeneration == generation else { return }
                    self.state.liveStroke = nil
                }
            case .cancelled:
                state.liveStroke = nil
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            changeCallsDuringStroke = 0
            strokeStart = .now
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            let duration = strokeStart.map { ContinuousClock.now - $0 } ?? .zero
            state.record("PK stroke ended after \(DrawingProbeState.format(duration)); drawingDidChange during stroke: \(changeCallsDuringStroke)")
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying else { return }
            if strokeStart != nil { changeCallsDuringStroke += 1 }
            var strokes: [DrawingStroke] = []
            let drawing = canvasView.drawing
            if let size = drawing.strokes.last?.path.first?.size, size.width > 0, size.width != state.pencilKitPointWidth {
                state.pencilKitPointWidth = size.width
                state.record("PK point size of a drawn stroke: \(String(format: "%.2f × %.2f", size.width, size.height))")
            }
            let sampling: PencilKitBridge.Sampling = state.interpolatedSampling ? .interpolated(spacing: 2) : .controlPoints
            let duration = ContinuousClock().measure {
                strokes = PencilKitBridge.strokes(from: drawing, mapping: mapping, sampling: sampling)
            }
            state.replaceStrokesFromCanvas(strokes)
            let points = strokes.reduce(0) { $0 + $1.points.count }
            state.record("PKDrawing → model: \(strokes.count) strokes, \(points) pts, \(DrawingProbeState.format(duration))")
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            if let item = toolPicker.selectedToolItem as? PKToolPickerInkingItem,
               let color = StrokeColor(cgColor: item.inkingTool.color.cgColor) {
                state.color = color
            }
        }
    }
}

/// Observes the touches of one stroke from the first contact on and never
/// recognizes, so it does not interfere with PencilKit's own gestures.
/// A second finger cancels the stroke, because PencilKit does not draw then.
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

    override func reset() { tracked = nil }

    private func finish(_ phase: Phase) {
        if tracked != nil { onTouches?(phase, [], tracked?.type == .pencil) }
        tracked = nil
        state = .failed
    }

    private func locations(of touch: UITouch, _ event: UIEvent) -> [CGPoint] {
        (event.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: view) }
    }
}
#endif
