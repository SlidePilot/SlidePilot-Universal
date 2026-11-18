import Foundation
import SlidePilotCore
#if canImport(AppKit)
import AppKit
/// The platform font of the notes editor.
public typealias NotesFont = NSFont
#elseif canImport(UIKit)
import UIKit
/// The platform font of the notes editor.
public typealias NotesFont = UIFont
#endif

/// The text notes of one document while they are edited (NOTES-04, NOTES-05).
///
/// Wraps the stored `CompanionNotes` and converts single pages between RTF and the
/// attributed strings of the AppKit/UIKit text view, so a keystroke only encodes its own
/// page. Text colors are never stored: the editor shows the system text color in light
/// and dark mode (NOTES-04, NOTES-09).
public struct TextNotes: Sendable, Equatable {
    /// The smallest and largest notes font size (NOTES-05). The old app had no limits, and
    /// a size of 0 or less turned into the default size.
    public static let fontSizes: ClosedRange<CGFloat> = 6...200

    public private(set) var notes: CompanionNotes

    /// Throws for notes in a format this version cannot read, so they are never shown
    /// wrongly or overwritten.
    public init(_ notes: CompanionNotes?) throws(LegacyNotesRTFError) {
        let notes = notes ?? CompanionNotes(format: .rtf, pages: [])
        guard notes.format == .rtf else { throw .unreadable }
        self.notes = notes
    }

    /// The notes of a page; pages beyond the stored ones have none (NOTES-10).
    public func page(_ index: Int) throws(LegacyNotesRTFError) -> NSAttributedString {
        guard notes.pages.indices.contains(index) else { return NSAttributedString() }
        return try Self.decode(notes.pages[index])
    }

    /// Stores the notes of a page. Colors are removed (see above).
    public mutating func setPage(_ index: Int, to text: NSAttributedString) throws(LegacyNotesRTFError) {
        guard index >= 0 else { return }
        let data = try Self.encode(text)
        if index >= notes.pages.count {
            guard !data.isEmpty else { return }
            notes.pages.append(contentsOf: Array(repeating: Data(), count: index + 1 - notes.pages.count))
        }
        notes.pages[index] = data
    }

    /// The notes font size: the size of the first text on `page`, else of the first text on
    /// any page, else `defaultSize`. The old app took the size of the text view's font.
    public func fontSize(onPage page: Int, defaultSize: CGFloat) -> CGFloat {
        let order = [page] + notes.pages.indices.filter { $0 != page }
        for index in order {
            guard let text = try? self.page(index), text.length > 0 else { continue }
            if let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NotesFont {
                return font.pointSize
            }
        }
        return defaultSize
    }

    /// Changes the font size of all pages by `delta` points, based on `fontSize(onPage:)`
    /// (NOTES-05). Every text gets the new size; bold, italic and the font family are kept
    /// (the old app replaced every font with the plain system font, DEF-13). Returns the
    /// new size.
    @discardableResult
    public mutating func changeFontSize(
        by delta: CGFloat, onPage page: Int, defaultSize: CGFloat
    ) throws(LegacyNotesRTFError) -> CGFloat {
        let current = fontSize(onPage: page, defaultSize: defaultSize)
        let size = min(max(current + delta, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        guard size != current else { return current }
        for index in notes.pages.indices where !notes.pages[index].isEmpty {
            let text = NSMutableAttributedString(attributedString: try self.page(index))
            Self.setFontSize(size, in: text)
            notes.pages[index] = try Self.encode(text)
        }
        return size
    }

    // MARK: - Conversion

    private static func setFontSize(_ size: CGFloat, in text: NSMutableAttributedString) {
        let all = NSRange(location: 0, length: text.length)
        var changes: [(NSRange, NotesFont)] = []
        text.enumerateAttribute(.font, in: all) { value, range, _ in
            let font = (value as? NotesFont).map { resized($0, to: size) } ?? NotesFont.systemFont(ofSize: size)
            changes.append((range, font))
        }
        for (range, font) in changes {
            text.addAttribute(.font, value: font, range: range)
        }
    }

    private static func resized(_ font: NotesFont, to size: CGFloat) -> NotesFont {
        #if canImport(AppKit)
        NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        #else
        font.withSize(size)
        #endif
    }

    static func encode(_ text: NSAttributedString) throws(LegacyNotesRTFError) -> Data {
        guard text.length > 0 else { return Data() }
        let stored = NSMutableAttributedString(attributedString: text)
        let all = NSRange(location: 0, length: stored.length)
        stored.removeAttribute(.foregroundColor, range: all)
        stored.removeAttribute(.backgroundColor, range: all)
        // Notes have no images (NOTES-04).
        stored.removeAttribute(.attachment, range: all)
        do {
            return try stored.data(from: all, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        } catch {
            throw .unwritable
        }
    }

    static func decode(_ data: Data) throws(LegacyNotesRTFError) -> NSAttributedString {
        guard !data.isEmpty else { return NSAttributedString() }
        do {
            return try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } catch {
            throw .unreadable
        }
    }
}
