import SlidePilotCore
import SlidePilotRendering
import SwiftUI

extension View {
    /// The drawing of `page`, read-only, over a slide surface (DRAW-01): presentation, current
    /// slide outside draw mode, next-slide preview and thumbnails. Apply it to the
    /// `SlideSurface` itself, so it has the slide's frame. Later layers (e.g. the pointer)
    /// stack as further overlays on top.
    func drawingOverlay(_ drawings: DocumentDrawings, page: Int, region: PageRegion = .full) -> some View {
        overlay {
            ReadOnlyDrawingLayer(drawings: drawings, page: page, region: region)
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

    var body: some View {
        Group {
            #if os(macOS)
            MacDrawingLayer(model: model, page: page, section: region.drawingSection)
            #else
            PencilDrawingLayer(model: model, page: page, section: region.drawingSection)
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

    var body: some View {
        let drawings = model.drawings
        let live = drawings.liveStroke.flatMap { $0.page == page ? $0.stroke : nil }
        GeometryReader { proxy in
            let mapping = CanvasMapping(section: section, canvasWidth: proxy.size.width, canvasHeight: proxy.size.height)
            DrawingCanvas(drawing: drawings.drawing(onPage: page), liveStroke: live, section: section)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard mapping.isValid else { return }
                            let point = mapping.relative(x: value.location.x, y: value.location.y)
                            if drawings.liveStroke == nil {
                                drawings.beginLiveStroke(onPage: page, at: [point])
                            } else {
                                drawings.extendLiveStroke(with: [point])
                            }
                        }
                        .onEnded { _ in
                            model.commitLiveStroke()
                        }
                )
        }
    }
}
#endif
