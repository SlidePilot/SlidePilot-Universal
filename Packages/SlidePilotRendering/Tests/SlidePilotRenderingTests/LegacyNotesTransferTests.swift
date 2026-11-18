import Foundation
import SlidePilotCore
@testable import SlidePilotRendering
import Testing

private func fixture(_ name: String, filePath: String = #filePath) throws -> Data {
    let root = URL(filePath: filePath)
        .deletingLastPathComponent() // SlidePilotRenderingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SlidePilotRendering
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
    return try Data(contentsOf: root.appending(path: "Fixtures/\(name)"))
}

private func texts(_ notes: CompanionNotes) throws -> [String] {
    try CompanionNotesRTF.pages(from: notes).map { String($0.characters) }
}

@Suite struct LegacyNotesTransferTests {
    // NOTES-09: a legacy file becomes one companion page per slide.
    @Test func importsTheFixtureIntoCompanionNotes() throws {
        let notes = try LegacyNotesTransfer.notes(fromLegacyRTF: fixture("plain-slides-notes.rtf"), pageCount: 6)
        #expect(notes.format == .rtf)
        let pages = try texts(notes)
        #expect(pages.count == 6)
        #expect(pages[0] == "Welcome. Notes for the title slide.")
        #expect(pages[4].isEmpty)
        #expect(notes.pages[4].isEmpty)
    }

    // NOTES-09: missing pages are filled with empty ones.
    @Test func padsToThePageCount() throws {
        let notes = try LegacyNotesTransfer.notes(fromLegacyRTF: fixture("links_Notizen.rtf"), pageCount: 5)
        let pages = try texts(notes)
        #expect(pages.count == 5)
        #expect(pages[2] == "Notes for page 3. The separator has no number.")
        #expect(pages[3...].allSatisfy { $0.isEmpty })
    }

    // NOTES-09: extra pages are kept.
    @Test func keepsPagesBeyondThePageCount() throws {
        let notes = try LegacyNotesTransfer.notes(fromLegacyRTF: fixture("plain-slides-notes.rtf"), pageCount: 2)
        #expect(try texts(notes).count == 6)
    }

    // DEF-11: an unreadable file fails instead of yielding partial or empty notes.
    @Test func rejectsFilesThatAreNotRTF() {
        #expect(throws: LegacyNotesRTFError.unreadable) {
            try LegacyNotesTransfer.notes(fromLegacyRTF: Data("plain text".utf8), pageCount: 3)
        }
    }

    // An RTF document without separators would replace the notes with empty ones.
    @Test func rejectsRTFWithoutSeparators() {
        let data = Data(#"{\rtf1\ansi Some unrelated document.\par}"#.utf8)
        #expect(throws: LegacyNotesRTFError.noPages) {
            try LegacyNotesTransfer.notes(fromLegacyRTF: data, pageCount: 3)
        }
    }

    // NOTES-06: the export is a legacy file with one page per slide.
    @Test func exportsOnePagePerSlide() throws {
        let stored = try CompanionNotesRTF.notes(fromPages: [AttributedString("First")])
        let data = try LegacyNotesTransfer.legacyRTF(from: stored, pageCount: 3)
        let pages = try LegacyNotesRTF.pages(fromRTF: data).map { String($0.characters) }
        #expect(pages == ["First", "", ""])
    }

    @Test func exportsEmptyPagesWithoutNotes() throws {
        let data = try LegacyNotesTransfer.legacyRTF(from: nil, pageCount: 2)
        #expect(try LegacyNotesRTF.pages(fromRTF: data).map { String($0.characters) } == ["", ""])
    }

    // NOTES-10: notes of pages beyond the PDF are not dropped on export.
    @Test func exportKeepsPagesBeyondThePageCount() throws {
        let stored = try CompanionNotesRTF.notes(fromPages: ["A", "B", "C"].map { AttributedString($0) })
        let data = try LegacyNotesTransfer.legacyRTF(from: stored, pageCount: 1)
        #expect(try LegacyNotesRTF.pages(fromRTF: data).map { String($0.characters) } == ["A", "B", "C"])
    }

    @Test func exportRejectsUnknownFormats() {
        let notes = CompanionNotes(format: CompanionNotes.Format(rawValue: "future"), pages: [Data([1])])
        #expect(throws: LegacyNotesRTFError.unreadable) {
            try LegacyNotesTransfer.legacyRTF(from: notes, pageCount: 1)
        }
    }

    // The old app reads what the new one exports, and the round trip keeps the text.
    @Test func fixtureSurvivesImportAndExport() throws {
        let imported = try LegacyNotesTransfer.notes(fromLegacyRTF: fixture("plain-slides-notes.rtf"), pageCount: 6)
        let exported = try LegacyNotesTransfer.legacyRTF(from: imported, pageCount: 6)
        let reimported = try LegacyNotesTransfer.notes(fromLegacyRTF: exported, pageCount: 6)
        #expect(try texts(reimported) == texts(imported))
    }
}
