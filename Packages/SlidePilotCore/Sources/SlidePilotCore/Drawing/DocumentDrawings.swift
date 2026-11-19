import Observation

/// The stroke being drawn right now, before it is added to the page. Read-only views show
/// it live, so the audience sees the line while it is drawn (DRAW-01).
public struct LiveStroke: Sendable, Hashable {
    public var page: Int
    public var stroke: DrawingStroke

    public init(page: Int, stroke: DrawingStroke) {
        self.page = page
        self.stroke = stroke
    }
}

/// The drawings of one document and the draw mode (DRAW-01 to DRAW-08).
///
/// The single source of truth for every surface (ADR 0016): the editable canvas (Mac layer,
/// iPad PencilKit) writes here, and the read-only views (presentation, next-slide preview,
/// thumbnails) render from here. Each page has its own undo history, so undo only ever
/// changes the visible slide (DRAW-08).
@MainActor
@Observable
public final class DocumentDrawings {
    /// Whether draw mode is on (DRAW-01).
    public private(set) var isDrawing = false

    /// The color of new strokes; black when a document opens, like the old app.
    public private(set) var color: StrokeColor = .black

    /// The color used before the current one, for the Apple Pencil "switch to last used"
    /// action (DRAW-11).
    public private(set) var previousColor: StrokeColor?

    /// "Save drawings" (DRAW-06). Off: the drawing is deleted when draw mode ends and the
    /// slide cannot change while drawing. On: drawings stay per page and slides can change.
    /// The setting itself comes with #32; until then it stays off.
    public var keepsDrawings = false

    /// The drawings by page index. Pages without an entry have an empty drawing.
    public private(set) var pages: [Int: PageDrawing] = [:]

    /// The stroke in progress, `nil` when no pen or mouse is down.
    public private(set) var liveStroke: LiveStroke?

    private var histories: [Int: PageHistory] = [:]

    public init() {}

    // MARK: - Draw mode

    /// Slides may change unless draw mode is on without "Save drawings" (NAV-04).
    public var allowsPageSwitching: Bool {
        !isDrawing || keepsDrawings
    }

    /// Turns draw mode on for `page` (DRAW-01).
    public func startDrawing(onPage page: Int) {
        guard !isDrawing else { return }
        isDrawing = true
        if !keepsDrawings {
            // Without "Save drawings" every session starts on a clean page, like the old app.
            pages[page] = nil
        }
        histories.removeAll()
    }

    /// Turns draw mode off (DRAW-01). Without "Save drawings" the drawing of `page` is
    /// deleted (DRAW-06). The undo history always ends with draw mode (DRAW-08).
    public func stopDrawing(onPage page: Int) {
        guard isDrawing else { return }
        isDrawing = false
        liveStroke = nil
        if !keepsDrawings {
            pages[page] = nil
        }
        histories.removeAll()
    }

    // MARK: - Color

    /// Chooses the color of new strokes (DRAW-03).
    public func selectColor(_ newColor: StrokeColor) {
        guard newColor != color else { return }
        previousColor = color
        color = newColor
    }

    /// Switches to the previously used color (DRAW-11). Does nothing before a second color
    /// was used.
    public func switchToPreviousColor() {
        guard let previousColor else { return }
        selectColor(previousColor)
    }

    // MARK: - Reading

    public func drawing(onPage page: Int) -> PageDrawing {
        pages[page] ?? PageDrawing()
    }

    // MARK: - Editing

    /// Starts showing a stroke in progress on `page`.
    public func beginLiveStroke(onPage page: Int, at points: [RelativePoint]) {
        liveStroke = LiveStroke(page: page, stroke: DrawingStroke(color: color, points: points))
    }

    /// Adds points to the stroke in progress.
    public func extendLiveStroke(with points: [RelativePoint]) {
        guard !points.isEmpty else { return }
        liveStroke?.stroke.points += points
    }

    /// Drops the stroke in progress, e.g. when a second finger touches the screen.
    public func cancelLiveStroke() {
        liveStroke = nil
    }

    /// Adds the stroke in progress to its page. Returns the page when something changed, so
    /// the caller can register an undo action.
    @discardableResult
    public func commitLiveStroke() -> Int? {
        guard let liveStroke else { return nil }
        self.liveStroke = nil
        guard !liveStroke.stroke.points.isEmpty else { return nil }
        let page = liveStroke.page
        change(page) { $0.strokes.append(liveStroke.stroke) }
        return page
    }

    /// Replaces the strokes of `page` with what an input layer reports, e.g. PencilKit after
    /// a stroke ends. Ends the stroke in progress on that page. Returns whether something
    /// changed.
    @discardableResult
    public func replaceStrokes(_ strokes: [DrawingStroke], onPage page: Int) -> Bool {
        if liveStroke?.page == page {
            liveStroke = nil
        }
        return change(page) { $0.strokes = strokes }
    }

    /// Removes all strokes of `page`; the background stays (DRAW-04).
    @discardableResult
    public func clear(page: Int) -> Bool {
        change(page) { $0.clear() }
    }

    /// Sets the canvas background of `page`; this also removes its strokes (DRAW-04).
    @discardableResult
    public func setBackground(_ background: CanvasBackground, onPage page: Int) -> Bool {
        change(page) { $0.setBackground(background) }
    }

    // MARK: - Undo (DRAW-08)

    public func canUndo(onPage page: Int) -> Bool {
        histories[page]?.undoStack.isEmpty == false
    }

    public func canRedo(onPage page: Int) -> Bool {
        histories[page]?.redoStack.isEmpty == false
    }

    /// Restores the drawing of `page` before its last change. Returns whether it did.
    @discardableResult
    public func undo(onPage page: Int) -> Bool {
        guard var history = histories[page], let previous = history.undoStack.popLast() else { return false }
        history.redoStack.append(drawing(onPage: page))
        histories[page] = history
        store(previous, onPage: page)
        return true
    }

    /// Repeats the last undone change of `page`. Returns whether it did.
    @discardableResult
    public func redo(onPage page: Int) -> Bool {
        guard var history = histories[page], let next = history.redoStack.popLast() else { return false }
        history.undoStack.append(drawing(onPage: page))
        histories[page] = history
        store(next, onPage: page)
        return true
    }

    // MARK: - Reload

    /// Drops the drawings of pages that a recompiled PDF no longer has (DOC-08).
    public func pageCountChanged(to pageCount: Int) {
        pages = pages.filter { $0.key < pageCount }
        histories = histories.filter { $0.key < pageCount }
        if let liveStroke, liveStroke.page >= pageCount {
            self.liveStroke = nil
        }
    }

    // MARK: - Private

    /// Applies `edit` to the drawing of `page` and records the old drawing for undo, unless
    /// nothing changed (the old app recorded no-op clears too; undoing them did nothing).
    @discardableResult
    private func change(_ page: Int, _ edit: (inout PageDrawing) -> Void) -> Bool {
        let old = drawing(onPage: page)
        var new = old
        edit(&new)
        guard new != old else { return false }
        histories[page, default: PageHistory()].record(old)
        store(new, onPage: page)
        return true
    }

    private func store(_ drawing: PageDrawing, onPage page: Int) {
        pages[page] = drawing.isEmpty ? nil : drawing
    }
}

/// Undo and redo snapshots of one page.
private struct PageHistory {
    var undoStack: [PageDrawing] = []
    var redoStack: [PageDrawing] = []

    mutating func record(_ old: PageDrawing) {
        undoStack.append(old)
        redoStack.removeAll()
    }
}
