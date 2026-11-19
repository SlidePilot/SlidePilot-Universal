import SlidePilotCore
import Testing

@Suite
struct PageDrawingTests {
    private let stroke = DrawingStroke(color: .blue, points: [RelativePoint(x: 0.1, y: 0.2)])

    @Test func clearKeepsTheBackground() {
        var drawing = PageDrawing(strokes: [stroke], background: .white)
        drawing.clear()
        #expect(drawing.strokes.isEmpty)
        #expect(drawing.background == .white)
    }

    // DRAW-04: switching the background clears the strokes.
    @Test func settingTheBackgroundClearsStrokes() {
        var drawing = PageDrawing(strokes: [stroke])
        drawing.setBackground(.white)
        #expect(drawing.strokes.isEmpty)
        #expect(drawing.background == .white)
        #expect(!drawing.isEmpty)
    }

    @Test func presetsAreTheOldToolbarColorsInOrder() {
        #expect(StrokeColor.presets == [.black, .white, .blue, .green, .magenta, .orange])
        #expect(StrokeColor.orange == StrokeColor(red: 1, green: 0.67, blue: 0))
    }

    @Test func presetMatchingToleratesRounding() {
        let rounded = StrokeColor(red: 18 / 255, green: 140 / 255, blue: 209 / 255)
        #expect(rounded.matchingPreset() == .blue)
        #expect(StrokeColor(red: 0.5, green: 0.5, blue: 0.5).matchingPreset() == nil)
    }
}

@Suite
struct CanvasMappingTests {
    @Test func fullPageScalesToTheCanvas() {
        let mapping = CanvasMapping(canvasWidth: 400, canvasHeight: 300)
        let point = mapping.relative(x: 100, y: 150)
        #expect(point == RelativePoint(x: 0.25, y: 0.5))
        let back = mapping.canvas(point)
        #expect(back.x == 100)
        #expect(back.y == 150)
    }

    // DRAW-02: a canvas that shows the right half of a split-notes page.
    @Test func halfPageSectionMapsIntoThatHalf() {
        let right = RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let mapping = CanvasMapping(section: right, canvasWidth: 200, canvasHeight: 300)
        #expect(mapping.relative(x: 0, y: 0) == RelativePoint(x: 0.5, y: 0))
        #expect(mapping.relative(x: 200, y: 300) == RelativePoint(x: 1, y: 1))
        #expect(mapping.relative(x: 100, y: 150) == RelativePoint(x: 0.75, y: 0.5))
    }

    // The same stroke lands on the same spot of the slide on a small presenter canvas and a
    // large presentation canvas.
    @Test func sameRelativePointOnDifferentCanvasSizes() {
        let presenter = CanvasMapping(canvasWidth: 640, canvasHeight: 480)
        let presentation = CanvasMapping(canvasWidth: 1920, canvasHeight: 1440)
        let point = presenter.relative(x: 320, y: 120)
        let onPresentation = presentation.canvas(point)
        #expect(onPresentation.x == 960)
        #expect(onPresentation.y == 360)
    }

    @Test func emptyCanvasIsInvalid() {
        #expect(!CanvasMapping(canvasWidth: 0, canvasHeight: 10).isValid)
        #expect(!CanvasMapping(section: RelativeRect(x: 0, y: 0, width: 0, height: 1), canvasWidth: 10, canvasHeight: 10).isValid)
        #expect(CanvasMapping(canvasWidth: 10, canvasHeight: 10).isValid)
    }
}

@MainActor
@Suite
struct DocumentDrawingsTests {
    private let a = RelativePoint(x: 0.1, y: 0.1)
    private let b = RelativePoint(x: 0.2, y: 0.3)

    private func draw(_ drawings: DocumentDrawings, onPage page: Int) {
        drawings.beginLiveStroke(onPage: page, at: [a])
        drawings.extendLiveStroke(with: [b])
        drawings.commitLiveStroke()
    }

    @Test func startsOutsideDrawModeWithBlack() {
        let drawings = DocumentDrawings()
        #expect(!drawings.isDrawing)
        #expect(drawings.color == .black)
        #expect(drawings.allowsPageSwitching)
    }

    // NAV-04: without "Save drawings" the slide cannot change while drawing.
    @Test func drawModeBlocksPageSwitchingUnlessDrawingsAreKept() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 0)
        #expect(!drawings.allowsPageSwitching)
        drawings.keepsDrawings = true
        #expect(drawings.allowsPageSwitching)
        drawings.stopDrawing(onPage: 0)
        drawings.keepsDrawings = false
        #expect(drawings.allowsPageSwitching)
    }

    @Test func liveStrokeIsShownUntilCommitted() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 2)
        drawings.selectColor(.orange)
        drawings.beginLiveStroke(onPage: 2, at: [a])
        drawings.extendLiveStroke(with: [b])
        #expect(drawings.liveStroke == LiveStroke(page: 2, stroke: DrawingStroke(color: .orange, points: [a, b])))
        #expect(drawings.drawing(onPage: 2).strokes.isEmpty)

        #expect(drawings.commitLiveStroke() == 2)
        #expect(drawings.liveStroke == nil)
        #expect(drawings.drawing(onPage: 2).strokes == [DrawingStroke(color: .orange, points: [a, b])])
    }

    @Test func cancelledLiveStrokeAddsNothing() {
        let drawings = DocumentDrawings()
        drawings.beginLiveStroke(onPage: 0, at: [a])
        drawings.cancelLiveStroke()
        #expect(drawings.commitLiveStroke() == nil)
        #expect(drawings.pages.isEmpty)
    }

    // DRAW-06 (off): leaving draw mode deletes the drawing, and entering starts clean.
    @Test func withoutSavingLeavingDrawModeDeletesTheDrawing() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 1)
        draw(drawings, onPage: 1)
        #expect(!drawings.drawing(onPage: 1).isEmpty)
        drawings.stopDrawing(onPage: 1)
        #expect(drawings.drawing(onPage: 1).isEmpty)
        #expect(drawings.pages.isEmpty)
    }

    // DRAW-06 (on, #32): drawings stay per page across draw mode and slide changes.
    @Test func keptDrawingsSurviveDrawMode() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        draw(drawings, onPage: 3)
        drawings.stopDrawing(onPage: 3)
        drawings.startDrawing(onPage: 0)
        #expect(drawings.drawing(onPage: 0).strokes.count == 1)
        #expect(drawings.drawing(onPage: 3).strokes.count == 1)
    }

    // DRAW-04: clear and white canvas.
    @Test func clearAndBackground() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        #expect(drawings.setBackground(.white, onPage: 0))
        #expect(drawings.drawing(onPage: 0) == PageDrawing(background: .white))
        draw(drawings, onPage: 0)
        #expect(drawings.clear(page: 0))
        #expect(drawings.drawing(onPage: 0) == PageDrawing(background: .white))
        #expect(drawings.setBackground(.transparent, onPage: 0))
        #expect(drawings.pages.isEmpty)
    }

    @Test func noOpChangesRecordNoUndo() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 0)
        #expect(!drawings.clear(page: 0))
        #expect(!drawings.setBackground(.transparent, onPage: 0))
        #expect(!drawings.canUndo(onPage: 0))
    }

    // DRAW-08: strokes, clear and background change are undoable, one history per page.
    @Test func undoAndRedoPerPage() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        drawings.setBackground(.white, onPage: 0)
        draw(drawings, onPage: 1)

        #expect(drawings.undo(onPage: 0))
        #expect(drawings.drawing(onPage: 0).strokes.count == 1)
        #expect(drawings.drawing(onPage: 0).background == .transparent)
        // Page 1 is untouched by undo on page 0.
        #expect(drawings.drawing(onPage: 1).strokes.count == 1)

        #expect(drawings.undo(onPage: 0))
        #expect(drawings.drawing(onPage: 0).isEmpty)
        #expect(!drawings.undo(onPage: 0))

        #expect(drawings.redo(onPage: 0))
        #expect(drawings.redo(onPage: 0))
        #expect(drawings.drawing(onPage: 0) == PageDrawing(background: .white))
        #expect(!drawings.canRedo(onPage: 0))
    }

    @Test func newChangeDropsRedo() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        drawings.undo(onPage: 0)
        #expect(drawings.canRedo(onPage: 0))
        draw(drawings, onPage: 0)
        #expect(!drawings.canRedo(onPage: 0))
    }

    // DRAW-08: the undo history ends with draw mode.
    @Test func leavingDrawModeClearsUndo() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        drawings.stopDrawing(onPage: 0)
        #expect(!drawings.canUndo(onPage: 0))
        #expect(drawings.drawing(onPage: 0).strokes.count == 1)
    }

    // PencilKit reports all strokes of the page when a stroke ends.
    @Test func replacingStrokesEndsTheLiveStrokeAndIsUndoable() {
        let drawings = DocumentDrawings()
        drawings.startDrawing(onPage: 0)
        drawings.beginLiveStroke(onPage: 0, at: [a])
        let reported = [DrawingStroke(color: .black, points: [a, b])]
        #expect(drawings.replaceStrokes(reported, onPage: 0))
        #expect(drawings.liveStroke == nil)
        #expect(!drawings.replaceStrokes(reported, onPage: 0))
        drawings.undo(onPage: 0)
        #expect(drawings.drawing(onPage: 0).isEmpty)
    }

    // DRAW-11: switch to the previously used color.
    @Test func previousColor() {
        let drawings = DocumentDrawings()
        drawings.switchToPreviousColor()
        #expect(drawings.color == .black)
        drawings.selectColor(.green)
        drawings.selectColor(.green)
        #expect(drawings.previousColor == .black)
        drawings.switchToPreviousColor()
        #expect(drawings.color == .black)
        drawings.switchToPreviousColor()
        #expect(drawings.color == .green)
    }

    @Test func shorterDeckDropsDrawingsOfRemovedPages() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        draw(drawings, onPage: 0)
        draw(drawings, onPage: 4)
        drawings.beginLiveStroke(onPage: 4, at: [a])
        drawings.pageCountChanged(to: 3)
        #expect(Array(drawings.pages.keys) == [0])
        #expect(drawings.liveStroke == nil)
        #expect(!drawings.canUndo(onPage: 4))
    }
}
