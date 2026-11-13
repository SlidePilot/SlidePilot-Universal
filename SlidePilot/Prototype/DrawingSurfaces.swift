import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// Page section plus drawing. Only the presenter surface is editable (DRAW-01).
struct SlideSurface: View {
    let state: DrawingProbeState
    let editable: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if let image = state.pageImage(pixelWidth: Int(size.width * displayScale)) {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                }
                overlay(size: size)
            }
        }
        .aspectRatio(state.sectionAspectRatio, contentMode: .fit)
        .border(.separator)
    }

    @ViewBuilder
    private func overlay(size: CGSize) -> some View {
        let mapping = CanvasMapping(section: state.section.rect, canvasWidth: size.width, canvasHeight: size.height)
        if !editable {
            DrawingPreview(drawing: state.displayedDrawing, mapping: mapping)
                .allowsHitTesting(false)
        } else {
            switch state.engine {
            case .custom:
                CustomDrawingLayer(state: state, mapping: mapping)
            case .pencilKit:
                #if os(iOS)
                ZStack {
                    // The canvas is transparent, so the white background is drawn below it.
                    DrawingPreview(drawing: PageDrawing(background: state.currentDrawing.background), mapping: mapping)
                        .allowsHitTesting(false)
                    PencilKitCanvas(state: state, mapping: mapping)
                }
                #else
                DrawingPreview(drawing: state.displayedDrawing, mapping: mapping)
                #endif
            }
        }
    }
}

/// Read-only rendering of the model, used for presentation, previews and thumbnails.
struct DrawingPreview: View {
    let drawing: PageDrawing
    let mapping: CanvasMapping

    var body: some View {
        Canvas { context, _ in
            context.withCGContext { cg in
                DrawingRenderer.draw(drawing, in: cg, mapping: mapping)
            }
        }
    }
}

/// Custom drawing layer: one `DragGesture` for mouse, trackpad, finger and Pencil.
struct CustomDrawingLayer: View {
    let state: DrawingProbeState
    let mapping: CanvasMapping
    @State private var strokeStart: ContinuousClock.Instant?

    var body: some View {
        DrawingPreview(drawing: state.displayedDrawing, mapping: mapping)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = mapping.relative(x: value.location.x, y: value.location.y)
                        if state.liveStroke == nil {
                            strokeStart = .now
                            state.liveStroke = DrawingStroke(color: state.color, points: [point])
                        } else {
                            state.liveStroke?.points.append(point)
                        }
                    }
                    .onEnded { _ in
                        guard let stroke = state.liveStroke else { return }
                        state.liveStroke = nil
                        state.addStroke(stroke)
                        let duration = strokeStart.map { ContinuousClock.now - $0 } ?? .zero
                        state.record("Custom stroke: \(stroke.points.count) pts in \(DrawingProbeState.format(duration)), mirrored live")
                    }
            )
    }
}
