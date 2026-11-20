import Foundation

/// The drawings of a document as stored in its companion file (DRAW-07).
///
/// The stored format is defined here on its own, not by the Codable conformances of the
/// drawing model, so it stays stable when the model changes and a `.slidepilot` export
/// (NOTES-11) can carry it as is:
///
/// ```json
/// {"format": "relative-strokes",
///  "pages": [{"page": 0, "background": "white",
///             "strokes": [{"color": [r, g, b, a], "points": [x0, y0, x1, y1, …]}]}]}
/// ```
///
/// Points are relative to the displayed page (DRAW-02) and rounded to 1/100 000 of the
/// page, which keeps the file small and is far below a pixel. Pages are in ascending order;
/// empty pages are not stored.
public struct CompanionDrawings: Sendable, Equatable {
    /// How the pages are encoded. A new encoding gets a new tag (and a new companion format
    /// version, so older apps never overwrite it).
    public struct Format: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Strokes as interleaved relative points with an sRGB color, one canvas background
        /// per page.
        public static let relativeStrokes = Format(rawValue: "relative-strokes")
    }

    public enum DecodingError: Error, Equatable {
        case unknownFormat(String)
        case invalidPage(Int)
        case oddPointCount
        case invalidColor
    }

    /// The drawing of each page by page index. Pages without an entry are empty.
    public var pages: [Int: PageDrawing]

    public init(pages: [Int: PageDrawing]) {
        self.pages = pages.filter { !$0.value.isEmpty }
    }

    public var isEmpty: Bool { pages.isEmpty }

    /// Points are stored with this precision (relative to the page).
    static let pointScale = 100_000.0
    /// Color channels are stored with this precision.
    static let colorScale = 10_000.0
}

extension CompanionDrawings: Codable {
    private enum CodingKeys: String, CodingKey {
        case format, pages
    }

    private struct StoredPage: Codable {
        var page: Int
        var background: CanvasBackground
        var strokes: [StoredStroke]
    }

    private struct StoredStroke: Codable {
        /// Red, green, blue and alpha in sRGB, 0…1.
        var color: [Double]
        /// x0, y0, x1, y1, …
        var points: [Double]
    }

    /// Strict: drawings that cannot be read fail the companion entry, so a save never
    /// replaces them with nothing (like the notes).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Format.self, forKey: .format)
        guard format == .relativeStrokes else {
            throw DecodingError.unknownFormat(format.rawValue)
        }
        var pages: [Int: PageDrawing] = [:]
        for stored in try container.decode([StoredPage].self, forKey: .pages) {
            guard stored.page >= 0, pages[stored.page] == nil else {
                throw DecodingError.invalidPage(stored.page)
            }
            let strokes = try stored.strokes.map { stroke in
                guard stroke.points.count.isMultiple(of: 2) else { throw DecodingError.oddPointCount }
                guard stroke.color.count == 4 else { throw DecodingError.invalidColor }
                let color = StrokeColor(red: stroke.color[0], green: stroke.color[1], blue: stroke.color[2], alpha: stroke.color[3])
                let points = stride(from: 0, to: stroke.points.count, by: 2).map {
                    RelativePoint(x: stroke.points[$0], y: stroke.points[$0 + 1])
                }
                return DrawingStroke(color: color, points: points)
            }
            pages[stored.page] = PageDrawing(strokes: strokes, background: stored.background)
        }
        self.init(pages: pages)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Format.relativeStrokes, forKey: .format)
        let stored = pages.keys.sorted().compactMap { index -> StoredPage? in
            guard let drawing = pages[index] else { return nil }
            return StoredPage(
                page: index,
                background: drawing.background,
                strokes: drawing.strokes.map { stroke in
                    let color = stroke.color
                    return StoredStroke(
                        color: [color.red, color.green, color.blue, color.alpha].map { Self.rounded($0, Self.colorScale) },
                        points: stroke.points.flatMap { [Self.rounded($0.x, Self.pointScale), Self.rounded($0.y, Self.pointScale)] }
                    )
                }
            )
        }
        try container.encode(stored, forKey: .pages)
    }

    private static func rounded(_ value: Double, _ scale: Double) -> Double {
        (value * scale).rounded() / scale
    }
}
