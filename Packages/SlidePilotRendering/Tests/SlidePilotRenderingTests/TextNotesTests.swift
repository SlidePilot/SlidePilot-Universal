import Foundation
import SlidePilotCore
@testable import SlidePilotRendering
import Testing
#if canImport(AppKit)
import AppKit
private typealias Color = NSColor
#else
import UIKit
private typealias Color = UIColor
#endif

@Suite
struct TextNotesTests {
    private func text(_ string: String, font: NotesFont = .systemFont(ofSize: 14), extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font].merging(extra) { $1 })
    }

    private func font(_ text: NSAttributedString, at index: Int = 0) throws -> NotesFont {
        try #require(text.attribute(.font, at: index, effectiveRange: nil) as? NotesFont)
    }

    private func isBold(_ font: NotesFont) -> Bool {
        #if canImport(AppKit)
        font.fontDescriptor.symbolicTraits.contains(.bold)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    private func isItalic(_ font: NotesFont) -> Bool {
        #if canImport(AppKit)
        font.fontDescriptor.symbolicTraits.contains(.italic)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    private var boldFont: NotesFont { .boldSystemFont(ofSize: 14) }

    private var italicFont: NotesFont {
        let plain = NotesFont.systemFont(ofSize: 14)
        #if canImport(AppKit)
        return NSFontManager.shared.convert(plain, toHaveTrait: .italicFontMask)
        #else
        return UIFont(descriptor: plain.fontDescriptor.withSymbolicTraits(.traitItalic)!, size: 14)
        #endif
    }

    // NOTES-10: pages beyond the stored ones have no notes; no notes stored yet is fine.
    @Test func readsMissingPagesAsEmpty() throws {
        let notes = try TextNotes(nil)
        #expect(try notes.page(3).length == 0)
        #expect(notes.notes == CompanionNotes(format: .rtf, pages: []))
    }

    @Test func rejectsUnknownFormats() {
        #expect(throws: LegacyNotesRTFError.unreadable) {
            try TextNotes(CompanionNotes(format: CompanionNotes.Format(rawValue: "future"), pages: [Data([1])]))
        }
    }

    // NOTES-04: notes are per page; writing a later page fills the pages before it.
    @Test func storesPagesAndFillsTheGap() throws {
        var notes = try TextNotes(nil)
        try notes.setPage(2, to: text("Third"))
        #expect(notes.notes.pages.count == 3)
        #expect(notes.notes.pages[0].isEmpty)
        #expect(notes.notes.pages[1].isEmpty)
        #expect(try notes.page(2).string == "Third")

        try notes.setPage(2, to: NSAttributedString())
        #expect(notes.notes.pages[2].isEmpty)
        #expect(notes.notes.isEmpty)
    }

    @Test func emptyTextOnANewPageAddsNothing() throws {
        var notes = try TextNotes(nil)
        try notes.setPage(5, to: NSAttributedString())
        #expect(notes.notes.pages.isEmpty)
    }

    // NOTES-04: bold, italic, underline and alignment survive storing.
    @Test func keepsFormatting() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let page = NSMutableAttributedString()
        page.append(text("Bold ", font: boldFont, extra: [.paragraphStyle: paragraph]))
        page.append(text("Italic ", font: italicFont, extra: [.paragraphStyle: paragraph]))
        page.append(text("Under", extra: [.underlineStyle: NSUnderlineStyle.single.rawValue, .paragraphStyle: paragraph]))

        var notes = try TextNotes(nil)
        try notes.setPage(0, to: page)
        let stored = try notes.page(0)

        #expect(stored.string == "Bold Italic Under")
        #expect(isBold(try font(stored, at: 0)))
        #expect(isItalic(try font(stored, at: 5)))
        #expect(stored.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        let style = try #require(stored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.alignment == .center)
    }

    // NOTES-04: the editor shows the system text color, so stored notes carry no colors.
    @Test func removesColors() throws {
        var notes = try TextNotes(nil)
        try notes.setPage(0, to: text("Red", extra: [.foregroundColor: Color.red, .backgroundColor: Color.yellow]))
        let stored = try notes.page(0)
        #expect(stored.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(stored.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    // NOTES-05: the size of the current page's text, else of any page, else the default.
    @Test func fontSizeComesFromTheText() throws {
        var notes = try TextNotes(nil)
        #expect(notes.fontSize(onPage: 0, defaultSize: 13) == 13)
        try notes.setPage(2, to: text("Big", font: .systemFont(ofSize: 30)))
        #expect(notes.fontSize(onPage: 0, defaultSize: 13) == 30)
        try notes.setPage(0, to: text("Small", font: .systemFont(ofSize: 10)))
        #expect(notes.fontSize(onPage: 0, defaultSize: 13) == 10)
        #expect(notes.fontSize(onPage: 2, defaultSize: 13) == 30)
    }

    // NOTES-05: ±1 pt applies to every page. DEF-13: bold and italic stay.
    @Test func changesTheFontSizeOfAllPagesAndKeepsTraits() throws {
        var notes = try TextNotes(nil)
        let first = NSMutableAttributedString()
        first.append(text("Bold", font: boldFont))
        first.append(text("Italic", font: italicFont))
        try notes.setPage(0, to: first)
        try notes.setPage(2, to: text("Other", font: .systemFont(ofSize: 20)))

        let size = try notes.changeFontSize(by: 1, onPage: 0, defaultSize: 13)
        #expect(size == 15)
        let page0 = try notes.page(0)
        #expect(try font(page0, at: 0).pointSize == 15)
        #expect(isBold(try font(page0, at: 0)))
        #expect(try font(page0, at: 4).pointSize == 15)
        #expect(isItalic(try font(page0, at: 4)))
        #expect(try font(try notes.page(2)).pointSize == 15)
        #expect(notes.notes.pages[1].isEmpty)

        #expect(try notes.changeFontSize(by: -1, onPage: 0, defaultSize: 13) == 14)
        #expect(try font(try notes.page(2)).pointSize == 14)
    }

    @Test func fontSizeStaysInItsRange() throws {
        var notes = try TextNotes(nil)
        try notes.setPage(0, to: text("Tiny", font: .systemFont(ofSize: TextNotes.fontSizes.lowerBound)))
        let before = notes
        #expect(try notes.changeFontSize(by: -1, onPage: 0, defaultSize: 13) == TextNotes.fontSizes.lowerBound)
        #expect(notes == before)
    }
}
