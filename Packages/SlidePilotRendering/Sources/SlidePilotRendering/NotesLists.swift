import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Automatic lists in the text notes (NOTES-13), like in Apple Notes: `* ` or `- ` at the
/// start of a line starts a list, Return on an empty item and Backspace at the start of
/// an item end it.
///
/// The lists are real `NSTextList`s in the paragraph style, so the Mac's List… panel and
/// the iPad's formatting panel can change them and RTF stores them (NOTES-10). The
/// markers are not part of the text: TextKit 2 draws them on both platforms
/// (`NSTextList.includesTextListMarkers` is `false`), and RTF writes them as list text
/// that the reader drops again, so lists look the same on the Mac and the iPad.
///
/// Each function returns the `Edit` that the text view applies with undo, or `nil` when
/// the key keeps its normal behavior.
public enum NotesList {
    public enum Kind: Sendable, CaseIterable {
        /// `* ` gives a bullet list (•).
        case bullet
        /// `- ` gives a dash list. It uses the system hyphen marker, the dashed list of the
        /// iPad's formatting panel; a custom "–" marker would be lost in RTF.
        case dash

        public var markerFormat: NSTextList.MarkerFormat {
            switch self {
            case .bullet: .disc
            case .dash: .hyphen
            }
        }

        var trigger: unichar {
            switch self {
            case .bullet: 0x2A // *
            case .dash: 0x2D // -
            }
        }
    }

    /// A replacement of `range` by `replacement`, then `selection` is selected and typing
    /// continues with `typingAttributes`.
    /// Not `Sendable`: it holds attributed strings and stays on the main actor.
    public struct Edit {
        public let range: NSRange
        public let replacement: NSAttributedString
        public let selection: NSRange
        /// The attributes for typing at the new selection, i.e. of the list paragraph.
        /// The empty last line of a text has no characters, so its paragraph style lives
        /// only here.
        public let typingAttributes: [NSAttributedString.Key: Any]

        public init(
            range: NSRange,
            replacement: NSAttributedString,
            selection: NSRange,
            typingAttributes: [NSAttributedString.Key: Any]? = nil
        ) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
            self.typingAttributes = typingAttributes
                ?? (replacement.length > 0 ? replacement.attributes(at: 0, effectiveRange: nil) : [:])
        }

        /// The edit that undoes this one in `text`, taken before applying it, with the
        /// selection and typing attributes of that moment.
        public func inverse(
            in text: NSAttributedString,
            selection previous: NSRange,
            typingAttributes previousTyping: [NSAttributedString.Key: Any]
        ) -> Edit {
            Edit(
                range: NSRange(location: range.location, length: replacement.length),
                replacement: text.attributedSubstring(from: range),
                selection: previous,
                typingAttributes: previousTyping
            )
        }

        public func apply(to text: NSMutableAttributedString) {
            text.replaceCharacters(in: range, with: replacement)
        }
    }

    /// After a space was typed in front of `caret`: `* ` or `- ` that opens a paragraph
    /// outside a list turns the paragraph into a list item. Anywhere else in a line, and
    /// in a paragraph that already is a list item, the characters stay text.
    public static func editAfterTypingSpace(in text: NSAttributedString, caret: Int) -> Edit? {
        let string = text.string as NSString
        guard caret >= 2, caret <= string.length, string.character(at: caret - 1) == 0x20 else { return nil }
        let start = caret - 2
        guard let kind = Kind.allCases.first(where: { $0.trigger == string.character(at: start) }) else { return nil }
        let paragraph = string.paragraphRange(for: NSRange(location: start, length: 0))
        guard paragraph.location == start, lists(in: text, at: start).isEmpty else { return nil }

        let rest = NSRange(location: caret, length: NSMaxRange(paragraph) - caret)
        let item = NSMutableAttributedString(attributedString: text.attributedSubstring(from: rest))
        if item.length == 0 {
            // The last paragraph of the notes without text: a line break carries the list's
            // paragraph style, as the text views do for a new empty item.
            item.append(NSAttributedString(string: "\n", attributes: text.attributes(at: start, effectiveRange: nil)))
        }
        let style = paragraphStyle(of: text, at: start, lists: [list(of: kind, around: paragraph, in: text)])
        item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
        return Edit(range: paragraph, replacement: item, selection: NSRange(location: start, length: 0))
    }

    /// Return on an empty list item ends the list there. `typingAttributes` are the text
    /// view's: they hold the list of an empty last line.
    public static func editForReturn(
        in text: NSAttributedString,
        selection: NSRange,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> Edit? {
        guard selection.length == 0 else { return nil }
        let string = text.string as NSString
        let paragraph = string.paragraphRange(for: selection)
        guard contentLength(of: paragraph, in: string) == 0 else { return nil }
        return removingList(from: paragraph, in: text, caret: selection.location, typingAttributes: typingAttributes)
    }

    /// Backspace at the start of a list item removes its marker (one list level) and
    /// keeps the text, instead of joining the item with the line above.
    public static func editForBackspace(
        in text: NSAttributedString,
        selection: NSRange,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> Edit? {
        guard selection.length == 0 else { return nil }
        let string = text.string as NSString
        let paragraph = string.paragraphRange(for: selection)
        guard paragraph.location == selection.location else { return nil }
        return removingList(from: paragraph, in: text, caret: selection.location, typingAttributes: typingAttributes)
    }

    // MARK: - Helpers

    private static func removingList(
        from paragraph: NSRange,
        in text: NSAttributedString,
        caret: Int,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> Edit? {
        let caretSelection = NSRange(location: caret, length: 0)
        guard paragraph.length > 0 else {
            // The empty last line: only the typing attributes change.
            guard let style = typingAttributes[.paragraphStyle] as? NSParagraphStyle, !style.textLists.isEmpty,
                  let plain = style.mutableCopy() as? NSMutableParagraphStyle
            else { return nil }
            plain.textLists.removeLast()
            var attributes = typingAttributes
            attributes[.paragraphStyle] = plain
            return Edit(range: paragraph, replacement: NSAttributedString(), selection: caretSelection, typingAttributes: attributes)
        }
        let lists = lists(in: text, at: paragraph.location)
        guard !lists.isEmpty else { return nil }
        let item = NSMutableAttributedString(attributedString: text.attributedSubstring(from: paragraph))
        let style = paragraphStyle(of: text, at: paragraph.location, lists: Array(lists.dropLast()))
        item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
        return Edit(range: paragraph, replacement: item, selection: caretSelection)
    }

    /// The paragraph's length without its line break.
    private static func contentLength(of paragraph: NSRange, in string: NSString) -> Int {
        var end = 0
        var contentsEnd = 0
        string.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: paragraph)
        return contentsEnd - paragraph.location
    }

    static func lists(in text: NSAttributedString, at location: Int) -> [NSTextList] {
        guard location < text.length else { return [] }
        return (text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []
    }

    private static func paragraphStyle(of text: NSAttributedString, at location: Int, lists: [NSTextList]) -> NSParagraphStyle {
        let current = location < text.length ? text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle : nil
        let style = (current ?? .default).mutableCopy() as! NSMutableParagraphStyle
        style.textLists = lists
        return style
    }

    /// The list of the item above or below when it has the same marker, so the items
    /// form one list (one RTF list, one list for VoiceOver); else a new list.
    private static func list(of kind: Kind, around paragraph: NSRange, in text: NSAttributedString) -> NSTextList {
        let neighbors = [paragraph.location - 1, NSMaxRange(paragraph)].filter { $0 >= 0 && $0 < text.length }
        for location in neighbors {
            if let list = lists(in: text, at: location).first, list.markerFormat == kind.markerFormat {
                return list
            }
        }
        return NSTextList(markerFormat: kind.markerFormat, options: 0)
    }
}
