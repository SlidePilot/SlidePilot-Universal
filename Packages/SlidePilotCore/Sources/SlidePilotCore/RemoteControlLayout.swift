import Foundation

/// What the controller shows of the presentation it controls (REM-07, layout button).
public enum RemoteControlLayout: String, CaseIterable, Sendable {
    /// The current and the next slide.
    case currentAndNext
    /// The current slide and its notes (notes image in split notes mode, and notes text).
    case currentAndNotes
    /// The current slide alone, as large as possible.
    case current

    public static let `default` = RemoteControlLayout.currentAndNext

    /// Whether the layout shows the next slide.
    public var showsNext: Bool { self == .currentAndNext }
    /// Whether the layout shows the notes.
    public var showsNotes: Bool { self == .currentAndNotes }
}
