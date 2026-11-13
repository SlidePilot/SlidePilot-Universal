import Foundation

/// The page format of the old app's notes files (NOTES-09).
///
/// Each page starts with a line `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-N`, followed by
/// the page's notes and a newline. The RTF encoding itself lives in SlidePilotRendering,
/// because reading RTF needs AppKit or UIKit.
public enum LegacyNotesFormat {
    /// Start of every separator line. The page number and a newline follow.
    public static let separatorPrefix = "#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-"

    /// Splits the text of a legacy notes file into pages.
    ///
    /// Like the old loader, page numbers are ignored (pages are taken in file order),
    /// a separator without a number is accepted and text before the first separator
    /// is dropped. One trailing newline per page is removed, because the writer adds it.
    /// Text without any separator yields no pages.
    public static func pages(from text: AttributedString) -> [AttributedString] {
        let string = String(String.UnicodeScalarView(text.unicodeScalars))
        // Unicode scalar semantics, so "\r\n" is never treated as one "\n" grapheme
        // and the offsets below map one to one onto the attributed string.
        let separator = /#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-[0-9]*\n/
            .matchingSemantics(.unicodeScalar)
        let scalars = string.unicodeScalars
        let offsets = string.matches(of: separator).map { match in
            (
                start: scalars.distance(from: scalars.startIndex, to: match.range.lowerBound),
                end: scalars.distance(from: scalars.startIndex, to: match.range.upperBound)
            )
        }

        func index(_ offset: Int) -> AttributedString.Index {
            text.unicodeScalars.index(text.startIndex, offsetBy: offset)
        }

        let totalCount = scalars.count
        return offsets.indices.map { i in
            let start = offsets[i].end
            var end = i + 1 < offsets.count ? offsets[i + 1].start : totalCount
            // DEF-12: the old code also removed a "\n" from empty pages and built a
            // negative range when two separators were adjacent.
            if end > start, scalars[scalars.index(scalars.startIndex, offsetBy: end - 1)] == "\n" {
                end -= 1
            }
            return AttributedString(text[index(start)..<index(end)])
        }
    }

    /// Joins pages into the text of a legacy notes file, numbering the pages from 1.
    ///
    /// The result keeps every attribute of the pages; separators carry no attributes.
    public static func text(from pages: [AttributedString]) -> AttributedString {
        var result = AttributedString()
        for (i, page) in pages.enumerated() {
            result += AttributedString("\(separatorPrefix)\(i + 1)\n")
            result += page
            result += AttributedString("\n")
        }
        return result
    }

    /// Pads `pages` with empty pages up to `pageCount`, like the old loader.
    /// Extra pages are kept, so notes survive when slides are removed and added back.
    public static func pages(_ pages: [AttributedString], paddedTo pageCount: Int) -> [AttributedString] {
        guard pages.count < pageCount else { return pages }
        return pages + Array(repeating: AttributedString(), count: pageCount - pages.count)
    }
}
