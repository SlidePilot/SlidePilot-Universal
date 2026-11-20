import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns the RTF notes a host sends (REM-04) into text SwiftUI shows with its fonts,
/// underline and strikethrough. Stored notes have no colors (NOTES-04), so the text uses
/// the system text color in light and dark mode.
enum RemoteNotesText {
    static func attributedString(from rtf: Data) -> AttributedString? {
        guard !rtf.isEmpty,
              let text = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        else { return nil }
        var result = AttributedString()
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var run = AttributedString(text.attributedSubstring(from: range).string)
            #if os(macOS)
            if let font = attributes[.font] as? NSFont {
                run.font = Font(font as CTFont)
            }
            #else
            if let font = attributes[.font] as? UIFont {
                run.font = Font(font as CTFont)
            }
            #endif
            if let style = attributes[.underlineStyle] as? Int, style != 0 {
                run.underlineStyle = .single
            }
            if let style = attributes[.strikethroughStyle] as? Int, style != 0 {
                run.strikethroughStyle = .single
            }
            result += run
        }
        return result.characters.isEmpty ? nil : result
    }
}
