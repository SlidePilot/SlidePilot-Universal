import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct LegacyNotesFormatTests {
    private let sep = LegacyNotesFormat.separatorPrefix

    private func strings(_ pages: [AttributedString]) -> [String] {
        pages.map { String($0.characters) }
    }

    @Test func splitsPagesInFileOrder() {
        let text = AttributedString("\(sep)1\nFirst\n\(sep)2\nSecond\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["First", "Second"])
    }

    @Test func keepsMultipleLinesAndEmptyLinesInsideAPage() {
        let text = AttributedString("\(sep)1\nLine one\nLine two\n\nAfter gap\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["Line one\nLine two\n\nAfter gap"])
    }

    @Test func dropsTextBeforeTheFirstSeparator() {
        let text = AttributedString("Preamble\n\(sep)1\nPage\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["Page"])
    }

    @Test func ignoresPageNumbersAndAcceptsMissingNumbers() {
        let text = AttributedString("\(sep)1\nA\n\(sep)7\nB\n\(sep)\nC\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["A", "B", "C"])
    }

    @Test func textWithoutSeparatorsHasNoPages() {
        #expect(LegacyNotesFormat.pages(from: AttributedString("Just some text\n")).isEmpty)
        #expect(LegacyNotesFormat.pages(from: AttributedString()).isEmpty)
    }

    @Test func aSeparatorWithoutNewlineIsNotASeparator() {
        // The old regex requires the newline; keep that.
        let text = AttributedString("\(sep)1\nA\n\(sep)2")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["A\n\(sep)2"])
    }

    @Test func removesOnlyOneTrailingNewline() {
        let text = AttributedString("\(sep)1\nA\n\n\n\(sep)2\nB")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["A\n\n", "B"])
    }

    // DEF-12: adjacent separators produced a negative range in the old app.
    @Test func adjacentSeparatorsGiveEmptyPages() {
        let text = AttributedString("\(sep)1\n\(sep)2\n\(sep)3\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["", "", ""])
    }

    @Test func anEmptyLineAsPageGivesAnEmptyPage() {
        let text = AttributedString("\(sep)1\n\n\(sep)2\nB\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["", "B"])
    }

    @Test func carriageReturnsStayInThePage() {
        let text = AttributedString("\(sep)1\nA\r\n\(sep)2\nB\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["A\r", "B"])
    }

    @Test func handlesNonASCIIAndEmoji() {
        let text = AttributedString("Ü\(sep)1\näöü ß é\n\(sep)2\n👩‍👩‍👧 🇩🇪\n")
        #expect(strings(LegacyNotesFormat.pages(from: text)) == ["äöü ß é", "👩‍👩‍👧 🇩🇪"])
    }

    @Test func keepsAttributesOfPageText() {
        var bold = AttributedString("Bold")
        bold.inlinePresentationIntent = .stronglyEmphasized
        let text = AttributedString("\(sep)1\n") + bold + AttributedString(" plain\n")
        let page = try! #require(LegacyNotesFormat.pages(from: text).first)
        let runs = page.runs.map { (String(page[$0.range].characters), $0.inlinePresentationIntent) }
        #expect(runs.count == 2)
        #expect(runs[0].0 == "Bold" && runs[0].1 == .stronglyEmphasized)
        #expect(runs[1].0 == " plain" && runs[1].1 == nil)
    }

    @Test func writesSeparatorsNumberedFromOne() {
        let text = LegacyNotesFormat.text(from: [AttributedString("A"), AttributedString(""), AttributedString("C")])
        #expect(String(text.characters) == "\(sep)1\nA\n\(sep)2\n\n\(sep)3\nC\n")
    }

    @Test func writingNoPagesGivesEmptyText() {
        #expect(LegacyNotesFormat.text(from: []).characters.isEmpty)
    }

    @Test(arguments: [
        [String](),
        [""],
        ["A", "", "C"],
        ["Ends with newline\n", "\n", "\n\n"],
        ["Multi\nline\n\nnotes", "äöü 👩‍👩‍👧"],
    ])
    func roundTripsPages(_ pages: [String]) {
        let text = LegacyNotesFormat.text(from: pages.map { AttributedString($0) })
        #expect(strings(LegacyNotesFormat.pages(from: text)) == pages)
    }

    @Test func padsMissingPagesWithEmptyOnes() {
        let padded = LegacyNotesFormat.pages([AttributedString("A")], paddedTo: 3)
        #expect(strings(padded) == ["A", "", ""])
    }

    @Test func keepsExtraPagesWhenPadding() {
        let pages = [AttributedString("A"), AttributedString("B")]
        #expect(strings(LegacyNotesFormat.pages(pages, paddedTo: 1)) == ["A", "B"])
    }
}
