import Foundation
import SlidePilotCore

/// Moves text notes between the companion file (NOTES-10) and the old app's RTF notes files
/// (NOTES-06, NOTES-08, NOTES-09).
///
/// Synchronous and nonisolated: callers run it off the main actor, because large notes
/// files take a noticeable time to parse.
public enum LegacyNotesTransfer {
    /// The notes of a legacy notes file, for a PDF with `pageCount` pages.
    ///
    /// Missing pages are filled with empty ones and extra pages are kept, like the old
    /// loader. A file without any page separator is rejected instead of replacing the notes
    /// with empty ones (the old app loaded it as empty notes). Throws instead of returning
    /// partial notes, so the caller keeps the current notes (DEF-11).
    public static func notes(fromLegacyRTF data: Data, pageCount: Int) throws(LegacyNotesRTFError) -> CompanionNotes {
        let pages = try LegacyNotesRTF.pages(fromRTF: data)
        guard !pages.isEmpty else { throw .noPages }
        return try CompanionNotesRTF.notes(fromPages: LegacyNotesFormat.pages(pages, paddedTo: pageCount))
    }

    /// A legacy notes file with one page per slide of a PDF with `pageCount` pages. Notes
    /// of pages beyond the PDF are kept, so nothing stored is lost (NOTES-10).
    public static func legacyRTF(from notes: CompanionNotes?, pageCount: Int) throws(LegacyNotesRTFError) -> Data {
        var pages: [AttributedString] = []
        if let notes {
            pages = try CompanionNotesRTF.pages(from: notes)
        }
        return try LegacyNotesRTF.rtf(fromPages: LegacyNotesFormat.pages(pages, paddedTo: pageCount))
    }
}
