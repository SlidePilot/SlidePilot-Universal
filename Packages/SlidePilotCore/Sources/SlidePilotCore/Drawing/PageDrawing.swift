/// A point relative to the displayed page: (0, 0) is the top-left corner,
/// (1, 1) the bottom-right corner. Independent of view size and platform.
public struct RelativePoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in relative page coordinates.
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

/// The part of the page that is shown when split notes are active (DRAW-02).
public enum PageSection: String, Sendable, Hashable, Codable, CaseIterable {
    case full, left, right, top, bottom

    public var rect: RelativeRect {
        switch self {
        case .full: .fullPage
        case .left: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: RelativeRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: RelativeRect(x: 0, y: 0.5, width: 1, height: 0.5)
        }
    }
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

    // The six preset colors of the old drawing toolbar (DRAW-03).
    public static let black = StrokeColor(red: 0, green: 0, blue: 0)
    public static let white = StrokeColor(red: 1, green: 1, blue: 1)
    public static let blue = StrokeColor(red: 0.07, green: 0.55, blue: 0.82)
    public static let green = StrokeColor(red: 0.18, green: 0.76, blue: 0.12)
    public static let magenta = StrokeColor(red: 0.72, green: 0.18, blue: 0.45)
    public static let orange = StrokeColor(red: 1.0, green: 0.67, blue: 0.0)
    public static let presets: [StrokeColor] = [.black, .white, .blue, .green, .magenta, .orange]
}

public struct DrawingStroke: Sendable, Hashable, Codable {
    public var color: StrokeColor
    public var points: [RelativePoint]

    public init(color: StrokeColor, points: [RelativePoint] = []) {
        self.color = color
        self.points = points
    }
}

public enum CanvasBackground: String, Sendable, Hashable, Codable {
    case transparent, white
}

/// The drawing of one page (DRAW-02). A value type, so undo is a snapshot.
public struct PageDrawing: Sendable, Hashable, Codable {
    public var strokes: [DrawingStroke]
    public var background: CanvasBackground

    /// Line width in points of the view that shows the drawing (old app: 2 pt, DRAW-02).
    public static let lineWidth = 2.0

    public init(strokes: [DrawingStroke] = [], background: CanvasBackground = .transparent) {
        self.strokes = strokes
        self.background = background
    }

    public var isEmpty: Bool { strokes.isEmpty && background == .transparent }

    public mutating func clear() {
        strokes.removeAll()
    }

    /// Switching the background also clears the strokes (DRAW-04).
    public mutating func setBackground(_ newBackground: CanvasBackground) {
        strokes.removeAll()
        background = newBackground
    }
}

/// Maps between a canvas (a view of `canvasWidth` × `canvasHeight` that shows
/// `section` of the page, top-left origin) and relative page coordinates.
public struct CanvasMapping: Sendable, Hashable {
    public var section: RelativeRect
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(section: RelativeRect, canvasWidth: Double, canvasHeight: Double) {
        self.section = section
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    public func relative(x: Double, y: Double) -> RelativePoint {
        RelativePoint(
            x: section.x + x / canvasWidth * section.width,
            y: section.y + y / canvasHeight * section.height)
    }

    public func canvas(_ point: RelativePoint) -> (x: Double, y: Double) {
        ((point.x - section.x) / section.width * canvasWidth,
         (point.y - section.y) / section.height * canvasHeight)
    }
}
