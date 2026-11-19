import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The text notes of one document (NOTES-04, NOTES-05). Reads and writes the notes in the
/// companion file, which marks the document edited and saves them (NOTES-07, DOC-09).
@Observable
final class NotesModel {
    /// Whether the notes editor has the keyboard. Set to `false` to finish editing (⌘↩,
    /// Done, a click outside the editor).
    var isEditing = false

    @ObservationIgnored private let companion: DocumentCompanion

    /// Done, ⌘↩ or a click outside the editor (NOTES-04).
    func finishEditing() {
        if isEditing {
            isEditing = false
        }
    }

    init(companion: DocumentCompanion) {
        self.companion = companion
    }

    /// The stored notes; changes when the notes are edited or replaced.
    var stored: CompanionNotes? { companion.notes }

    /// The notes, or `nil` before the document's entry is loaded and for notes in a format
    /// this version cannot read.
    private var textNotes: TextNotes? {
        guard companion.entry != nil else { return nil }
        return try? TextNotes(companion.notes)
    }

    /// Notes can be edited once the document's entry is loaded and the notes are readable,
    /// and not while another entry's data is taken over (NOTES-12).
    var isAvailable: Bool { textNotes != nil && !companion.isTakingOver }

    /// Stored notes that this version cannot show, e.g. written by a later version.
    var isUnreadable: Bool {
        guard companion.entry != nil else { return false }
        return (try? TextNotes(companion.notes)) == nil
    }

    /// The notes of a page; `nil` if they cannot be shown.
    func text(forPage page: Int) -> NSAttributedString? {
        try? textNotes?.page(page)
    }

    /// The stored RTF of a page, for the remote (REM-04); `nil` if the page has no notes or
    /// they cannot be shown.
    func rtf(forPage page: Int) -> Data? {
        guard let notes = textNotes?.notes, notes.pages.indices.contains(page), !notes.pages[page].isEmpty else { return nil }
        return notes.pages[page]
    }

    /// Stores the edited notes of a page.
    func setText(_ text: NSAttributedString, forPage page: Int) {
        guard var notes = textNotes else { return }
        do {
            try notes.setPage(page, to: text)
        } catch {
            return
        }
        companion.setNotes(notes.notes)
    }

    /// The size for new text on a page (NOTES-05).
    func fontSize(forPage page: Int) -> CGFloat {
        textNotes?.fontSize(onPage: page, defaultSize: defaultFontSize) ?? defaultFontSize
    }

    /// Format ▸ Font ▸ Bigger / Smaller: ±1 pt on all pages, marks the document edited (NOTES-05).
    func changeFontSize(by delta: CGFloat, onPage page: Int) {
        guard var notes = textNotes else { return }
        let original = notes.notes
        let before = notes.fontSize(onPage: page, defaultSize: defaultFontSize)
        guard let size = try? notes.changeFontSize(by: delta, onPage: page, defaultSize: defaultFontSize),
              size != before
        else { return }
        if notes.notes == original {
            // No text yet: only new text gets the size.
            emptyNotesFontSize = size
        } else {
            companion.setNotes(notes.notes)
        }
    }

    /// The size chosen with Bigger/Smaller while the notes had no text yet. Kept for the
    /// open document only, like the old app's text view font (not a preference).
    private var emptyNotesFontSize: CGFloat?

    /// The size of new notes: the system's body text size.
    private var defaultFontSize: CGFloat {
        emptyNotesFontSize ?? NotesFont.preferredFont(forTextStyle: .body).pointSize
    }
}
