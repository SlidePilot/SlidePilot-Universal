import Foundation
import SlidePilotCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Converts text notes to and from the companion file (NOTES-10): one RTF document per
/// page. RTF names fonts instead of storing `NSFont`/`UIFont` objects, so the same notes
/// open on the Mac and the iPad. Lives here because RTF needs AppKit or UIKit.
public enum CompanionNotesRTF {
    /// The notes of each page, encoded for the companion file. Empty pages stay empty data.
    public static func notes(fromPages pages: [AttributedString]) throws(LegacyNotesRTFError) -> CompanionNotes {
        var encoded: [Data] = []
        for page in pages {
            encoded.append(try rtf(from: page))
        }
        return CompanionNotes(format: .rtf, pages: encoded)
    }

    /// The pages of stored notes. Throws for a format this version cannot read, so the
    /// caller never shows or overwrites notes it did not understand.
    public static func pages(from notes: CompanionNotes) throws(LegacyNotesRTFError) -> [AttributedString] {
        guard notes.format == .rtf else { throw .unreadable }
        var pages: [AttributedString] = []
        for data in notes.pages {
            pages.append(try page(fromRTF: data))
        }
        return pages
    }

    private static func rtf(from page: AttributedString) throws(LegacyNotesRTFError) -> Data {
        guard !page.characters.isEmpty else { return Data() }
        let attributed: NSAttributedString
        do {
            #if canImport(AppKit)
            attributed = try NSAttributedString(page, including: \.appKit)
            #else
            attributed = try NSAttributedString(page, including: \.uiKit)
            #endif
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            throw .unwritable
        }
    }

    private static func page(fromRTF data: Data) throws(LegacyNotesRTFError) -> AttributedString {
        guard !data.isEmpty else { return AttributedString() }
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } catch {
            throw .unreadable
        }
        return try LegacyNotesRTF.platformAttributedString(attributed)
    }
}
