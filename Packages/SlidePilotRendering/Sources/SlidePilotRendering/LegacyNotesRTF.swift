import Foundation
import SlidePilotCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Why a legacy notes file could not be imported or exported.
public enum LegacyNotesRTFError: Error, Equatable, Sendable {
    /// The data is not a readable RTF document.
    case unreadable
    /// The notes could not be written as RTF.
    case unwritable
}

/// Reads and writes the old app's RTF notes files (NOTES-06, NOTES-09).
///
/// Lives here and not in SlidePilotCore because RTF needs the AppKit or UIKit
/// attributed-string extensions. The page format itself is `LegacyNotesFormat` in Core.
public enum LegacyNotesRTF {
    /// Reads the pages of a legacy notes file.
    ///
    /// Text colors are removed: the old app wrote every file in black (DEF-12), which
    /// would be unreadable in dark mode, so the notes use the system text color instead.
    /// Throws instead of returning partial notes, so the caller never keeps stale
    /// notes by accident (DEF-11).
    public static func pages(fromRTF data: Data) throws(LegacyNotesRTFError) -> [AttributedString] {
        let attributed: NSMutableAttributedString
        do {
            attributed = try NSMutableAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } catch {
            throw .unreadable
        }
        let all = NSRange(location: 0, length: attributed.length)
        attributed.removeAttribute(.foregroundColor, range: all)
        // Notes have no images (NOTES-04), and attachments are mutable reference values
        // that should not cross actors inside the returned string.
        attributed.removeAttribute(.attachment, range: all)
        return LegacyNotesFormat.pages(from: try platformAttributedString(attributed))
    }

    /// Writes pages as a legacy notes file that the old app and TextEdit can read.
    ///
    /// Unlike the old app, this keeps the notes' own attributes and does not force
    /// black text, and it writes real RTF (DEF-12).
    public static func rtf(fromPages pages: [AttributedString]) throws(LegacyNotesRTFError) -> Data {
        let text = LegacyNotesFormat.text(from: pages)
        let attributed: NSAttributedString
        do {
            #if canImport(AppKit)
            attributed = try NSAttributedString(text, including: \.appKit)
            #else
            attributed = try NSAttributedString(text, including: \.uiKit)
            #endif
        } catch {
            throw .unwritable
        }
        do {
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            throw .unwritable
        }
    }

    private static func platformAttributedString(
        _ attributed: NSAttributedString
    ) throws(LegacyNotesRTFError) -> AttributedString {
        do {
            #if canImport(AppKit)
            return try AttributedString(attributed, including: \.appKit)
            #else
            return try AttributedString(attributed, including: \.uiKit)
            #endif
        } catch {
            throw .unreadable
        }
    }
}
