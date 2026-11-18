import Foundation

/// What to do with a legacy notes file next to a PDF when the PDF opens (NOTES-08).
public enum LegacyNotesAutoLoad: Equatable, Sendable {
    /// Nothing to load.
    case none
    /// Read `file` with the access of the granted `folder`.
    case load(file: URL, folder: URL)
    /// The app sees `file` but may not read it: ask the user for access to its folder.
    case askForFolder(file: URL)

    /// Decides what to do for an opened PDF.
    ///
    /// Notes stored in the companion file win: a legacy file is only loaded while the PDF
    /// has no notes yet, so later edits are never replaced by the old file. A PDF whose
    /// folder grant the user declined is not asked about again.
    /// - Parameters:
    ///   - notesFile: The first existing legacy notes file (`LegacyNotesFileName`), if any.
    ///   - grantedFolder: The granted folder that contains `notesFile`, if any.
    public static func action(
        notesFile: URL?,
        hasNotes: Bool,
        declined: Bool,
        grantedFolder: URL?
    ) -> LegacyNotesAutoLoad {
        guard let notesFile, !hasNotes else { return .none }
        if let grantedFolder {
            return .load(file: notesFile, folder: grantedFolder)
        }
        return declined ? .none : .askForFolder(file: notesFile)
    }
}
