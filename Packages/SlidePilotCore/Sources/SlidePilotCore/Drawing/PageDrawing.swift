/// A point relative to the displayed page (after `/Rotate`): (0, 0) is the top-left corner,
/// (1, 1) the bottom-right corner. Independent of view size and platform (DRAW-02).
public struct RelativePoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in relative page coordinates, e.g. the half of a split-notes page that a
/// canvas shows.
public struct RelativeRect: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let fullPage = RelativeRect(x: 0, y: 0, width: 1, height: 1)
}

/// sRGB color of a stroke.
public struct StrokeColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    // The six preset colors of the old drawing toolbar (DRAW-03, `DrawingToolbar.swift:23-28`).
    public static let black = StrokeColor(red: 0, green: 0, blue: 0)
    public static let white = StrokeColor(red: 1, green: 1, blue: 1)
    public static let blue = StrokeColor(red: 0.07, green: 0.55, blue: 0.82)
    public static let green = StrokeColor(red: 0.18, green: 0.76, blue: 0.12)
    public static let magenta = StrokeColor(red: 0.72, green: 0.18, blue: 0.45)
    public static let orange = StrokeColor(red: 1.0, green: 0.67, blue: 0.0)

    /// In the old toolbar's order.
    public static let presets: [StrokeColor] = [.black, .white, .blue, .green, .magenta, .orange]

    /// The preset this color is closest to within `tolerance` per channel, if any. Colors that
    /// went through a platform color (e.g. PencilKit) come back with small rounding errors.
    public func matchingPreset(tolerance: Double = 1.5 / 255) -> StrokeColor? {
        Self.presets.first { preset in
            abs(preset.red - red) <= tolerance && abs(preset.green - green) <= tolerance
                && abs(preset.blue - blue) <= tolerance && abs(preset.alpha - alpha) <= tolerance
        }
    }
}

/// One line drawn without lifting the pen.
public struct DrawingStroke: Sendable, Hashable, Codable {
    public var color: StrokeColor
    public var points: [RelativePoint]

    public init(color: StrokeColor, points: [RelativePoint] = []) {
        self.color = color
        self.points = points
    }
}

/// What lies below the strokes (DRAW-04).
public enum CanvasBackground: String, Sendable, Hashable, Codable, CaseIterable {
    /// The slide shows through.
    case transparent
    /// A white sheet covers the slide.
    case white
}

/// The drawing of one page (DRAW-02). A value type, so undo keeps snapshots.
public struct PageDrawing: Sendable, Hashable, Codable {
    public var strokes: [DrawingStroke]
    public var background: CanvasBackground

    /// Line width in points of the view that shows the drawing (DRAW-02), on every surface.
    public static let lineWidth = 2.0

    public init(strokes: [DrawingStroke] = [], background: CanvasBackground = .transparent) {
        self.strokes = strokes
        self.background = background
    }

    /// Nothing to show: no strokes on a transparent canvas.
    public var isEmpty: Bool { strokes.isEmpty && background == .transparent }

    /// Removes all strokes; the background stays (DRAW-04, there is no stroke eraser).
    public mutating func clear() {
        strokes.removeAll()
    }

    /// Switching the background also clears the strokes (DRAW-04).
    public mutating func setBackground(_ newBackground: CanvasBackground) {
        strokes.removeAll()
        background = newBackground
    }
}

/// Maps between a canvas (a view of `canvasWidth` × `canvasHeight`, top-left origin) that
/// shows `section` of a page, and relative page coordinates (DRAW-02). Split notes show half
/// a page; the drawing stays one per page, only the mapping differs.
public struct CanvasMapping: Sendable, Hashable {
    public var section: RelativeRect
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(section: RelativeRect = .fullPage, canvasWidth: Double, canvasHeight: Double) {
        self.section = section
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    /// Whether points can be mapped; an empty canvas or section has no scale.
    public var isValid: Bool {
        canvasWidth > 0 && canvasHeight > 0 && section.width > 0 && section.height > 0
    }

    public func relative(x: Double, y: Double) -> RelativePoint {
        RelativePoint(
            x: section.x + x / canvasWidth * section.width,
            y: section.y + y / canvasHeight * section.height
        )
    }

    public func canvas(_ point: RelativePoint) -> (x: Double, y: Double) {
        (
            (point.x - section.x) / section.width * canvasWidth,
            (point.y - section.y) / section.height * canvasHeight
        )
    }
}
