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
        // PencilKit reports a change only when a stroke ends. Following its
        // drawing gesture lets the presentation mirror the stroke live.
        canvas.drawingGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.followDrawingGesture(_:)))
        let picker = PKToolPicker(toolItems: [
            PKToolPickerInkingItem(type: .monoline, color: Self.uiColor(state.color), width: PageDrawing.lineWidth),
        ])
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

        if coordinator.appliedRevision != state.externalRevision || coordinator.appliedMapping != mapping {
            let drawing = state.currentDrawing
            var pk = PKDrawing()
            let duration = ContinuousClock().measure {
                pk = PencilKitBridge.pkDrawing(from: drawing, mapping: mapping)
            }
            coordinator.isApplying = true
            canvas.drawing = pk
            coordinator.isApplying = false
            coordinator.appliedRevision = state.externalRevision
            coordinator.appliedMapping = mapping
            state.record("Model → PKDrawing: \(drawing.strokes.count) strokes, \(DrawingProbeState.format(duration))")
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

    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        let state: DrawingProbeState
        var toolPicker: PKToolPicker?
        var mapping = CanvasMapping(section: .fullPage, canvasWidth: 1, canvasHeight: 1)
        var appliedRevision = -1
        var appliedMapping: CanvasMapping?
        var isApplying = false
        private var changeCallsDuringStroke = 0
        private var strokeStart: ContinuousClock.Instant?

        init(state: DrawingProbeState) { self.state = state }

        @objc func followDrawingGesture(_ recognizer: UIGestureRecognizer) {
            guard state.liveMirrorsPencilKit else { return }
            let location = recognizer.location(in: recognizer.view)
            let point = mapping.relative(x: location.x, y: location.y)
            switch recognizer.state {
            case .began:
                state.liveStroke = DrawingStroke(color: state.color, points: [point])
            case .changed:
                state.liveStroke?.points.append(point)
            default:
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
            let sampling: PencilKitBridge.Sampling = state.interpolatedSampling ? .interpolated(spacing: 2) : .controlPoints
            let duration = ContinuousClock().measure {
                strokes = PencilKitBridge.strokes(from: drawing, mapping: mapping, sampling: sampling)
            }
            state.replaceStrokesFromCanvas(strokes)
            let points = strokes.reduce(0) { $0 + $1.points.count }
            state.record("PKDrawing → model: \(strokes.count) strokes, \(points) pts, \(DrawingProbeState.format(duration))")
        }

        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            if let item = toolPicker.selectedToolItem as? PKToolPickerInkingItem,
               let color = StrokeColor(cgColor: item.inkingTool.color.cgColor) {
                state.color = color
            }
        }
    }
}
#endif
