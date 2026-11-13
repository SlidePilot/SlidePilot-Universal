import Foundation
import SlidePilotCore
import Testing
@testable import SlidePilotRendering
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Reads a file from the repository's `Fixtures/` folder.
///
/// Tests run unhosted (no app sandbox), on the Mac and in the simulator, so the source
/// tree is readable through `#filePath`. That avoids a second copy of each fixture.
private func fixtureData(_ name: String, filePath: String = #filePath) throws -> Data {
    let root = URL(filePath: filePath)
        .deletingLastPathComponent() // SlidePilotRenderingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SlidePilotRendering
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
    return try Data(contentsOf: root.appending(path: "Fixtures/\(name)"))
}

private func strings(_ pages: [AttributedString]) -> [String] {
    pages.map { String($0.characters) }
}

private func nsAttributed(_ page: AttributedString) throws -> NSAttributedString {
    #if canImport(AppKit)
    try NSAttributedString(page, including: \.appKit)
    #else
    try NSAttributedString(page, including: \.uiKit)
    #endif
}

private func hasTrait(_ page: AttributedString, text: String, bold: Bool) throws -> Bool {
    let ns = try nsAttributed(page)
    let range = (ns.string as NSString).range(of: text)
    guard range.location != NSNotFound,
          let font = ns.attribute(.font, at: range.location, effectiveRange: nil) else { return false }
    #if canImport(AppKit)
    let traits = (font as? NSFont)?.fontDescriptor.symbolicTraits ?? []
    return bold ? traits.contains(.bold) : traits.contains(.italic)
    #else
    let traits = (font as? UIFont)?.fontDescriptor.symbolicTraits ?? []
    return bold ? traits.contains(.traitBold) : traits.contains(.traitItalic)
    #endif
}

@Suite struct LegacyNotesRTFTests {
    @Test func importsPlainSlidesFixture() throws {
        let pages = try LegacyNotesRTF.pages(fromRTF: fixtureData("plain-slides-notes.rtf"))
        #expect(strings(pages) == [
            "Welcome. Notes for the title slide.",
            "Notes for the bullet points.\nSecond line of the same page.\n\nParagraph after an empty line.",
            "Bold and italic text on the formula slide.",
            "Non-ASCII text: äöü ÄÖÜ ß éèà ç.",
            "",
            "Notes for the last slide.",
        ])
    }

    @Test func keepsBoldAndItalic() throws {
        let pages = try LegacyNotesRTF.pages(fromRTF: fixtureData("plain-slides-notes.rtf"))
        #expect(try hasTrait(pages[2], text: "Bold", bold: true))
        #expect(try hasTrait(pages[2], text: "italic", bold: false))
        #expect(try !hasTrait(pages[2], text: "text on", bold: true))
    }

    @Test func importsEdgeCaseFixture() throws {
        let pages = try LegacyNotesRTF.pages(fromRTF: fixtureData("links_Notizen.rtf"))
        // Preamble dropped, Page-7 and a missing number accepted, 3 pages for a 5-page PDF.
        #expect(strings(pages) == [
            "Notes for page 1 of links.pdf.",
            "Notes for page 2. The separator says Page-7: numbers are ignored.",
            "Notes for page 3. The separator has no number.",
        ])
        #expect(LegacyNotesFormat.pages(pages, paddedTo: 5).count == 5)
    }

    @Test func removesTheForcedBlackTextColor() throws {
        let pages = try LegacyNotesRTF.pages(fromRTF: fixtureData("plain-slides-notes.rtf"))
        for page in pages {
            let ns = try nsAttributed(page)
            var colors = 0
            ns.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
                if value != nil { colors += 1 }
            }
            #expect(colors == 0)
        }
    }

    // DEF-11: a file that cannot be read must fail, never yield stale or partial notes.
    @Test func rejectsDataThatIsNotRTF() {
        #expect(throws: LegacyNotesRTFError.unreadable) {
            try LegacyNotesRTF.pages(fromRTF: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]))
        }
    }

    @Test func rtfWithoutSeparatorsHasNoPages() throws {
        let data = Data(#"{\rtf1\ansi Some unrelated document.\par}"#.utf8)
        #expect(try LegacyNotesRTF.pages(fromRTF: data).isEmpty)
    }

    @Test func exportWritesRTFWithSeparators() throws {
        let data = try LegacyNotesRTF.rtf(fromPages: [AttributedString("First"), AttributedString("Second")])
        #expect(data.starts(with: Data(#"{\rtf1"#.utf8)))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\(LegacyNotesFormat.separatorPrefix)1"))
        #expect(text.contains("\(LegacyNotesFormat.separatorPrefix)2"))
    }

    // DEF-12: the old app forced black text on export.
    @Test func exportDoesNotForceATextColor() throws {
        let data = try LegacyNotesRTF.rtf(fromPages: [AttributedString("Plain")])
        let ns = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
        )
        #expect(ns.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func fixtureSurvivesExportAndImport() throws {
        let original = try LegacyNotesRTF.pages(fromRTF: fixtureData("plain-slides-notes.rtf"))
        let reimported = try LegacyNotesRTF.pages(fromRTF: LegacyNotesRTF.rtf(fromPages: original))
        #expect(strings(reimported) == strings(original))
        #expect(try hasTrait(reimported[2], text: "Bold", bold: true))
        #expect(try hasTrait(reimported[2], text: "italic", bold: false))
    }

    @Test func emptyAndTrailingNewlinePagesSurviveExport() throws {
        let pages = ["", "Ends with newline\n", "Multi\n\nline", "äöü 👩‍👩‍👧"]
        let data = try LegacyNotesRTF.rtf(fromPages: pages.map { AttributedString($0) })
        #expect(try strings(LegacyNotesRTF.pages(fromRTF: data)) == pages)
    }
}
