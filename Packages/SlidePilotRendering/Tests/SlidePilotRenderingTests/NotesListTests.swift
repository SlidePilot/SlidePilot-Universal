import Foundation
@testable import SlidePilotRendering
import Testing
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// NOTES-13: automatic bullet and dash lists in the text notes.
@Suite
struct NotesListTests {
    private let font = NotesFont.systemFont(ofSize: 14)

    private func text(_ string: String, list: NSTextList? = nil) -> NSMutableAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let list {
            let style = NSMutableParagraphStyle()
            style.textLists = [list]
            attributes[.paragraphStyle] = style
        }
        return NSMutableAttributedString(string: string, attributes: attributes)
    }

    private func applied(_ edit: NotesList.Edit?, to text: NSMutableAttributedString) throws -> NSMutableAttributedString {
        let edit = try #require(edit)
        edit.apply(to: text)
        return text
    }

    private func lists(_ text: NSAttributedString, at location: Int) -> [NSTextList] {
        NotesList.lists(in: text, at: location)
    }

    // MARK: - Starting a list

    @Test(arguments: [("*", NSTextList.MarkerFormat.disc), ("-", NSTextList.MarkerFormat.hyphen)])
    func markerAndSpaceStartAList(trigger: String, format: NSTextList.MarkerFormat) throws {
        let notes = text("Intro\n\(trigger) ")
        let edit = try #require(NotesList.editAfterTypingSpace(in: notes, caret: 8))
        #expect(edit.selection == NSRange(location: 6, length: 0))
        let result = try applied(edit, to: notes)
        // The typed characters are gone; a line break carries the empty last item.
        #expect(result.string == "Intro\n\n")
        #expect(lists(result, at: 6).map(\.markerFormat) == [format])
        #expect(lists(result, at: 0).isEmpty)
        #expect(edit.typingAttributes[.paragraphStyle] as? NSParagraphStyle == result.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle)
    }

    @Test func textAfterTheMarkerBecomesTheItem() throws {
        let notes = text("* Existing\nNext")
        let result = try applied(NotesList.editAfterTypingSpace(in: notes, caret: 2), to: notes)
        #expect(result.string == "Existing\nNext")
        #expect(lists(result, at: 0).count == 1)
        #expect(lists(result, at: 8).count == 1)
        #expect(lists(result, at: 9).isEmpty)
    }

    @Test func keepsFontAndOtherParagraphAttributes() throws {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let bold = NotesFont.boldSystemFont(ofSize: 20)
        let notes = NSMutableAttributedString(string: "- Item", attributes: [.font: bold, .paragraphStyle: style])
        let result = try applied(NotesList.editAfterTypingSpace(in: notes, caret: 2), to: notes)
        let paragraph = try #require(result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.alignment == .center)
        #expect(paragraph.textLists.map(\.markerFormat) == [.hyphen])
        #expect((result.attribute(.font, at: 0, effectiveRange: nil) as? NotesFont)?.pointSize == 20)
    }

    @Test(arguments: [
        ("Text * ", 7), // not at the start of the line
        ("** ", 3), // more than the marker
        (" * ", 3), // indented
        ("+ ", 2), // other characters
        ("*", 1), // no space yet
        ("*x", 2), // something else typed
    ])
    func elsewhereTheCharactersStayText(string: String, caret: Int) {
        #expect(NotesList.editAfterTypingSpace(in: text(string), caret: caret) == nil)
    }

    @Test func insideAListItemTheCharactersStayText() {
        let notes = text("* ", list: NSTextList(markerFormat: .disc, options: 0))
        #expect(NotesList.editAfterTypingSpace(in: notes, caret: 2) == nil)
    }

    @Test func newItemJoinsTheListAboveWithTheSameMarker() throws {
        let bullets = NSTextList(markerFormat: .disc, options: 0)
        let notes = text("One\n", list: bullets)
        notes.append(text("* "))
        let result = try applied(NotesList.editAfterTypingSpace(in: notes, caret: 6), to: notes)
        #expect(lists(result, at: 4).first === bullets)

        let dashes = text("One\n", list: bullets)
        dashes.append(text("- "))
        let other = try applied(NotesList.editAfterTypingSpace(in: dashes, caret: 6), to: dashes)
        #expect(lists(other, at: 4).first !== bullets)
        #expect(lists(other, at: 4).first?.markerFormat == .hyphen)
    }

    // MARK: - Ending a list

    @Test func returnOnAnEmptyItemEndsTheList() throws {
        let list = NSTextList(markerFormat: .disc, options: 0)
        let notes = text("One\n\n", list: list)
        let edit = try #require(NotesList.editForReturn(in: notes, selection: NSRange(location: 4, length: 0), typingAttributes: [:]))
        let result = try applied(edit, to: notes)
        #expect(result.string == "One\n\n")
        #expect(lists(result, at: 0).count == 1)
        #expect(lists(result, at: 4).isEmpty)
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }

    // The iPad keeps a new empty last item only in the typing attributes.
    @Test func returnAndBackspaceOnTheEmptyLastLineUseTheTypingAttributes() throws {
        let list = NSTextList(markerFormat: .disc, options: 0)
        let notes = text("One\n", list: list)
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        let typing: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let end = NSRange(location: 4, length: 0)
        for edit in [
            NotesList.editForReturn(in: notes, selection: end, typingAttributes: typing),
            NotesList.editForBackspace(in: notes, selection: end, typingAttributes: typing),
        ] {
            let edit = try #require(edit)
            #expect(edit.range == end)
            #expect(edit.replacement.length == 0)
            #expect((edit.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.isEmpty == true)
            #expect(edit.typingAttributes[.font] as? NotesFont == font)
        }
        #expect(NotesList.editForReturn(in: notes, selection: end, typingAttributes: [.font: font]) == nil)
    }

    @Test func returnInAnItemWithTextKeepsTheNormalBehavior() {
        let notes = text("One\n", list: NSTextList(markerFormat: .disc, options: 0))
        #expect(NotesList.editForReturn(in: notes, selection: NSRange(location: 3, length: 0), typingAttributes: [:]) == nil)
        #expect(NotesList.editForReturn(in: notes, selection: NSRange(location: 0, length: 0), typingAttributes: [:]) == nil)
        #expect(NotesList.editForReturn(in: text("\n"), selection: NSRange(location: 0, length: 0), typingAttributes: [:]) == nil)
    }

    @Test func backspaceAtTheStartOfAnItemRemovesTheMarker() throws {
        let list = NSTextList(markerFormat: .hyphen, options: 0)
        let notes = text("One\n", list: list)
        notes.append(text("\n", list: list))
        let result = try applied(NotesList.editForBackspace(in: notes, selection: NSRange(location: 4, length: 0), typingAttributes: [:]), to: notes)
        #expect(result.string == "One\n\n")
        #expect(lists(result, at: 0).count == 1)
        #expect(lists(result, at: 4).isEmpty)

        let withText = text("Item", list: list)
        let kept = try applied(NotesList.editForBackspace(in: withText, selection: NSRange(location: 0, length: 0), typingAttributes: [:]), to: withText)
        #expect(kept.string == "Item")
        #expect(lists(kept, at: 0).isEmpty)
    }

    @Test func backspaceRemovesOneLevelOfANestedList() throws {
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .disc, options: 0), NSTextList(markerFormat: .hyphen, options: 0)]
        let notes = NSMutableAttributedString(string: "Inner", attributes: [.font: font, .paragraphStyle: style])
        let result = try applied(NotesList.editForBackspace(in: notes, selection: NSRange(location: 0, length: 0), typingAttributes: [:]), to: notes)
        #expect(lists(result, at: 0).map(\.markerFormat) == [.disc])
    }

    @Test func backspaceElsewhereKeepsTheNormalBehavior() {
        let notes = text("Item", list: NSTextList(markerFormat: .disc, options: 0))
        #expect(NotesList.editForBackspace(in: notes, selection: NSRange(location: 2, length: 0), typingAttributes: [:]) == nil)
        #expect(NotesList.editForBackspace(in: notes, selection: NSRange(location: 0, length: 2), typingAttributes: [:]) == nil)
        #expect(NotesList.editForBackspace(in: text("Plain"), selection: NSRange(location: 0, length: 0), typingAttributes: [:]) == nil)
    }

    // MARK: - Undo and storage

    @Test func inverseRestoresTheTypedCharacters() throws {
        let original = text("* ")
        let notes = NSMutableAttributedString(attributedString: original)
        let edit = try #require(NotesList.editAfterTypingSpace(in: notes, caret: 2))
        let inverse = edit.inverse(in: notes, selection: NSRange(location: 2, length: 0), typingAttributes: [:])
        edit.apply(to: notes)
        inverse.apply(to: notes)
        #expect(notes.isEqual(to: original))
        #expect(inverse.selection == NSRange(location: 2, length: 0))
    }

    // NOTES-10: lists survive the companion file's RTF with their marker, so a list made
    // on one platform shows the same marker on the other.
    @Test(arguments: NotesList.Kind.allCases)
    func listsSurviveStoring(kind: NotesList.Kind) throws {
        let page = text("Intro\n")
        page.append(text(kind == .bullet ? "* " : "- "))
        let edited = try applied(NotesList.editAfterTypingSpace(in: page, caret: 8), to: page)
        edited.insert(NSAttributedString(string: "Item", attributes: edited.attributes(at: 6, effectiveRange: nil)), at: 6)

        var notes = try TextNotes(nil)
        try notes.setPage(0, to: edited)
        let stored = try notes.page(0)
        #expect(stored.string == "Intro\nItem\n")
        #expect(lists(stored, at: 6).map(\.markerFormat) == [kind.markerFormat])
        #expect(lists(stored, at: 0).isEmpty)
    }
}
