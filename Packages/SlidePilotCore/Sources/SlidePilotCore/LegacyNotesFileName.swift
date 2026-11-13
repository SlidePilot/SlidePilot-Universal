import Foundation

/// File names of legacy notes files next to a PDF (NOTES-06, NOTES-08).
public enum LegacyNotesFileName {
    /// The old app's search order: every name for `-`, then for `_`, then for a space.
    /// On case-sensitive volumes `Notes` and `notes` are different files, so the order matters.
    static let separators = ["-", "_", " "]
    static let names = ["Notes", "notes", "Notizen"]
    static let pathExtension = "rtf"

    /// Candidate names for the notes of a PDF with the given base name (no extension),
    /// in the order the old app searched them.
    public static func candidates(forPDFBaseName baseName: String) -> [String] {
        separators.flatMap { separator in
            names.map { "\(baseName)\(separator)\($0).\(pathExtension)" }
        }
    }

    /// Candidate URLs next to the PDF, in search order.
    public static func candidates(forPDFAt pdfURL: URL) -> [URL] {
        let folder = pdfURL.deletingLastPathComponent()
        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        return candidates(forPDFBaseName: baseName).map {
            folder.appending(path: $0, directoryHint: .notDirectory)
        }
    }

    /// The first candidate for which `exists` returns `true`, or `nil`.
    public static func firstExisting(forPDFAt pdfURL: URL, exists: (URL) -> Bool) -> URL? {
        candidates(forPDFAt: pdfURL).first(where: exists)
    }

    /// Suggested name for an RTF export: `<pdf>-<Notes>.rtf`, or `Notes.rtf` without a PDF name
    /// (the old app did not localize that fallback).
    /// - Parameter localizedNotes: The localized word for "Notes" (the app passes it in).
    public static func exportName(forPDFBaseName baseName: String?, localizedNotes: String) -> String {
        guard let baseName, !baseName.isEmpty else { return "Notes.\(pathExtension)" }
        return "\(baseName)-\(localizedNotes).\(pathExtension)"
    }
}
