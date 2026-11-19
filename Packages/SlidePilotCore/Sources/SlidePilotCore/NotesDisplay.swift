/// How the notes slot shows the notes (NOTES-01).
public enum NotesMode: String, Codable, Sendable, CaseIterable {
    /// Rich-text notes per page (NOTES-04).
    case text
    /// Notes are half of each PDF page, as Beamer's "show notes on second screen" puts them.
    case split
}

/// Which half of each PDF page holds the notes in a split-notes deck (NOTES-02). The audience
/// sees the other half; `none` shows the whole page everywhere.
public enum NotesPosition: String, Codable, Sendable, CaseIterable {
    case none, right, left, bottom, top

    /// The position named by the PDF's keywords (NOTES-03): the first of the exact,
    /// case-sensitive keywords `SP-Right`, `SP-Left`, `SP-Top` and `SP-Bottom`.
    public init?(pdfKeywords keywords: [String]) {
        for keyword in keywords {
            switch keyword {
            case "SP-Right": self = .right
            case "SP-Left": self = .left
            case "SP-Top": self = .top
            case "SP-Bottom": self = .bottom
            default: continue
            }
            return
        }
        return nil
    }
}

/// The notes mode and split position of a document (NOTES-01 to NOTES-03).
///
/// The two depend on each other only while the notes slot is shown, like in the old app
/// (`AppDelegate.notesModeDidChange`, `notesPositionDidChange`, `displayNotesDidChange`):
/// choosing Split sets the position Right if it was None, choosing Text sets None, and
/// choosing None switches to Text. With the notes slot hidden, each can be set on its own;
/// the position still decides which half the audience sees.
public struct NotesDisplay: Sendable, Equatable {
    public private(set) var mode: NotesMode
    public private(set) var position: NotesPosition

    /// Text notes on whole pages, the old app's state before a PDF's keywords are read.
    public static let `default` = NotesDisplay(mode: .text, position: .none)

    public init(mode: NotesMode, position: NotesPosition) {
        self.mode = mode
        self.position = position
    }

    /// The state when a PDF opens (NOTES-03): Split at the keyword's position, or the default.
    /// Stored per-document settings are applied afterwards and win (SET-02).
    public init(pdfKeywords keywords: [String]) {
        if let position = NotesPosition(pdfKeywords: keywords) {
            self.init(mode: .split, position: position)
        } else {
            self = .default
        }
    }

    /// Whether the notes slot shows half of the page (NOTES-01, NOTES-02).
    public var showsSplitNotes: Bool {
        mode == .split && position != .none
    }

    public mutating func setMode(_ newMode: NotesMode, notesShown: Bool) {
        mode = newMode
        guard notesShown else { return }
        switch newMode {
        case .text: position = .none
        case .split where position == .none: position = .right
        case .split: break
        }
    }

    public mutating func setPosition(_ newPosition: NotesPosition, notesShown: Bool) {
        position = newPosition
        if newPosition == .none, notesShown, mode == .split {
            mode = .text
        }
    }

    /// Call when the notes slot appears: Split without a position shows the right half.
    public mutating func notesDidShow() {
        if mode == .split, position == .none {
            position = .right
        }
    }
}
