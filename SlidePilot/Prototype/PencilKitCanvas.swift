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
        // With a finger, the drawing gesture begins only after some movement
        // (to tell drawing from scrolling). The tracker sees the touch from
        // its start, so the mirror gets the beginning of the stroke too.
        let tracker = TouchTracker()
        tracker.delegate = context.coordinator
        canvas.addGestureRecognizer(tracker)
        context.coordinator.tracker = tracker
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
            let width = coordinator.inkPointWidth
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
        var tracker: TouchTracker?
        /// Point size PencilKit stores for a monoline stroke drawn at width 2.
        /// Rebuilt strokes need the same size, or they look thinner. Measured
        /// from the first drawn stroke; until then the nominal width.
        var inkPointWidth = PageDrawing.lineWidth
        private var liveGeneration = 0
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
                liveGeneration += 1
                let earlier = (tracker?.locations ?? []).map { mapping.relative(x: $0.x, y: $0.y) }
                state.liveStroke = DrawingStroke(color: state.color, points: earlier + [point])
            case .changed:
                state.liveStroke?.points.append(point)
            case .ended:
                // Cleared by the model update that follows, to avoid a flash.
                // Fallback in case PencilKit adds no stroke (nothing to update).
                state.liveStroke?.points.append(point)
                let generation = liveGeneration
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.liveGeneration == generation else { return }
                    self.state.liveStroke = nil
                }
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
            if let size = drawing.strokes.last?.path.first?.size, size.width > 0, size.width != inkPointWidth {
                inkPointWidth = size.width
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
final class TouchTracker: UIGestureRecognizer {
    private(set) var locations: [CGPoint] = []

    override init(target: Any? = nil, action: Selector? = nil) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard locations.isEmpty, let touch = touches.first else { return }
        append(touch, event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        append(touch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func reset() { locations = [] }

    private func append(_ touch: UITouch, _ event: UIEvent) {
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        locations += samples.map { $0.location(in: view) }
    }
}
#endif
