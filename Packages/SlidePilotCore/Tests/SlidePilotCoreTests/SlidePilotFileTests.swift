import Foundation
import SlidePilotCore
import Testing

// NOTES-11, ADR 0019: the .slidepilot file carries a PDF's notes, drawings and settings.
@Suite
struct SlidePilotFileFormatTests {
    private let notes = CompanionNotes(format: .rtf, pages: [Data("{\\rtf1 a}".utf8), Data(), Data("{\\rtf1 c}".utf8)])
    private let drawings = CompanionDrawings(pages: [
        1: PageDrawing(strokes: [DrawingStroke(color: .blue, points: [RelativePoint(x: 0.25, y: 0.5), RelativePoint(x: 0.75, y: 0.5)])], background: .white),
    ])

    private func entry() -> CompanionEntry {
        var settings = DocumentSettings(
            layout: PresenterLayout(arrangement: .single), isNavigatorDisplayed: true, declinedLegacyNotes: true,
            isPointerDisplayed: true
        )
        settings.notesMode = .split
        return CompanionEntry(
            pdf: PDFReference(bookmark: Data("/Users/someone/talk.pdf".utf8), fileName: "talk.pdf", pageCount: 3, documentIdentifier: 42),
            lastOpened: Date(timeIntervalSince1970: 1_000),
            settings: settings, notes: notes, drawings: drawings,
            declinedOrphans: [UUID()]
        )
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func roundTrip() throws {
        let file = SlidePilotFile(entry: entry(), exportedAt: Date(timeIntervalSince1970: 2_000))
        let decoded = try SlidePilotFileFormat.decode(SlidePilotFileFormat.encode(file))
        #expect(decoded == file)
        #expect(decoded.notes == notes)
        #expect(decoded.drawings == drawings)
        #expect(decoded.settings.layout?.arrangement == .single)
        #expect(decoded.settings.notesMode == .split)
        #expect(decoded.pdfFileName == "talk.pdf")
        #expect(decoded.pdfPageCount == 3)
        #expect(decoded.kinds == [.notes, .drawings, .settings])
    }

    // Nothing that only applies to one device, and no local path, ends up in the file.
    @Test func leavesOutDeviceState() throws {
        let data = try SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/Users"))
        #expect(!text.contains("bookmark"))
        #expect(!text.contains("documentIdentifier"))
        #expect(!text.contains("declinedOrphans"))
        #expect(!text.contains("declinedLegacyNotes"))
        #expect(!text.contains("lastOpened"))
        let object = try json(data)
        #expect(Set(object.keys) == ["slidePilotFileVersion", "exportedAt", "pdf", "settings", "notes", "drawings"])
        #expect(object["slidePilotFileVersion"] as? Int == 1)
    }

    // Empty notes, drawings and settings are left out; such a file still reads.
    @Test func emptyFile() throws {
        let file = SlidePilotFile(
            pdfFileName: "a.pdf", pdfPageCount: 1, exportedAt: Date(timeIntervalSince1970: 0),
            notes: CompanionNotes(format: .rtf, pages: [Data()]), drawings: CompanionDrawings(pages: [:])
        )
        #expect(file.notes == nil && file.drawings == nil && file.kinds.isEmpty)
        let data = try SlidePilotFileFormat.encode(file)
        #expect(Set(try json(data).keys) == ["slidePilotFileVersion", "exportedAt", "pdf"])
        #expect(try SlidePilotFileFormat.decode(data) == file)
    }

    // Unknown keys of a later version with the same number are ignored.
    @Test func ignoresUnknownKeys() throws {
        var object = try json(SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now)))
        object["comments"] = ["a", "b"]
        var pdf = try #require(object["pdf"] as? [String: Any])
        pdf["checksum"] = "abc"
        object["pdf"] = pdf
        let decoded = try SlidePilotFileFormat.decode(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.notes == notes)
    }

    // A later version may encode fields differently: refused instead of read in part.
    @Test func refusesNewerVersions() throws {
        var object = try json(SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now)))
        object["slidePilotFileVersion"] = SlidePilotFileFormat.currentVersion + 1
        #expect(throws: SlidePilotFileFormat.DecodingError.newerVersion) {
            try SlidePilotFileFormat.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test(arguments: [
        Data(),
        Data("not json".utf8),
        Data("{\"formatVersion\": 1, \"entry\": {}}".utf8),
        Data("{\"slidePilotFileVersion\": 0, \"exportedAt\": \"2026-01-01T00:00:00Z\", \"pdf\": {\"fileName\": \"a.pdf\", \"pageCount\": 1}}".utf8),
        Data("{\"slidePilotFileVersion\": 1, \"exportedAt\": \"2026-01-01T00:00:00Z\"}".utf8),
    ])
    func refusesOtherData(_ data: Data) {
        #expect(throws: SlidePilotFileFormat.DecodingError.unreadable) {
            try SlidePilotFileFormat.decode(data)
        }
    }

    // A companion file is not a .slidepilot file, and the other way round.
    @Test func isNotACompanionFile() throws {
        let companion = try CompanionFileFormat.encode(entry())
        #expect(throws: SlidePilotFileFormat.DecodingError.unreadable) {
            try SlidePilotFileFormat.decode(companion)
        }
        let file = try SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now))
        #expect(throws: CompanionFileFormat.DecodingError.unreadable) {
            try CompanionFileFormat.decode(file)
        }
    }

    // Damaged notes or drawings fail the import instead of replacing data with less.
    @Test(arguments: ["notes", "drawings"])
    func damagedContentIsRefused(_ key: String) throws {
        var object = try json(SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now)))
        object[key] = ["pages": 3]
        #expect(throws: SlidePilotFileFormat.DecodingError.unreadable) {
            try SlidePilotFileFormat.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    // A damaged setting falls back to "not saved", like in the companion file.
    @Test func damagedSettingIsSkipped() throws {
        var object = try json(SlidePilotFileFormat.encode(SlidePilotFile(entry: entry(), exportedAt: .now)))
        var settings = try #require(object["settings"] as? [String: Any])
        settings["layout"] = "broken"
        object["settings"] = settings
        let decoded = try SlidePilotFileFormat.decode(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.settings.layout == nil)
        #expect(decoded.settings.isNavigatorDisplayed == true)
    }

    @Test func mismatch() {
        let file = SlidePilotFile(pdfFileName: "talk.pdf", pdfPageCount: 3, exportedAt: .now)
        #expect(file.mismatch(withPDFNamed: "talk.pdf", pageCount: 3).isEmpty)
        #expect(file.mismatch(withPDFNamed: "other.pdf", pageCount: 3) == .fileName)
        #expect(file.mismatch(withPDFNamed: "talk.pdf", pageCount: 5) == .pageCount)
        #expect(file.mismatch(withPDFNamed: "other.pdf", pageCount: 2) == [.fileName, .pageCount])
        // Without a file name only the page count is compared.
        #expect(file.mismatch(withPDFNamed: nil, pageCount: 3).isEmpty)
    }

    @Test func exportName() {
        #expect(SlidePilotFile.exportName(forPDFBaseName: "talk", untitled: "Untitled") == "talk.slidepilot")
        #expect(SlidePilotFile.exportName(forPDFBaseName: nil, untitled: "Untitled") == "Untitled.slidepilot")
        #expect(SlidePilotFile.exportName(forPDFBaseName: "", untitled: "Untitled") == "Untitled.slidepilot")
    }

    // Settings in the file win; settings it does not hold stay as stored.
    @Test func settingsOverride() {
        var stored = DocumentSettings(layout: PresenterLayout(arrangement: .single), isNavigatorDisplayed: false, declinedLegacyNotes: true)
        stored.notesMode = .text
        var imported = DocumentSettings(isNavigatorDisplayed: true, isPointerDisplayed: true)
        imported.notesPosition = .right
        let result = stored.overridden(by: imported)
        #expect(result.layout?.arrangement == .single)
        #expect(result.isNavigatorDisplayed == true)
        #expect(result.isPointerDisplayed == true)
        #expect(result.notesMode == .text)
        #expect(result.notesPosition == .right)
        #expect(result.declinedLegacyNotes == true)
    }
}

@MainActor
@Suite
struct SlidePilotFileImportTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SlidePilotFileImportTests-\(UUID().uuidString)")
    let locator = FakeLocator()

    private func makeCompanion() -> DocumentCompanion {
        DocumentCompanion(store: CompanionStore(directory: directory, locator: locator), saveDelay: .milliseconds(10))
    }

    private let drawings = CompanionDrawings(pages: [0: PageDrawing(background: .white)])

    // NOTES-11: an import replaces notes and drawings, is saved and found on the next open.
    @Test func importReplacesAndIsSaved() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 2)
        companion.setNotes(CompanionNotes(format: .rtf, pages: [Data([9])]))
        companion.setDrawings(CompanionDrawings(pages: [1: PageDrawing(strokes: [DrawingStroke(color: .black, points: [RelativePoint(x: 0.5, y: 0.5)])])]))
        await companion.flush()

        let notes = CompanionNotes(format: .rtf, pages: [Data([1]), Data([2]), Data([3])])
        var settings = DocumentSettings(isPointerDisplayed: true)
        settings.notesMode = .split
        let file = SlidePilotFile(pdfFileName: "other.pdf", pdfPageCount: 3, exportedAt: .now, settings: settings, notes: notes, drawings: drawings)
        let applied = companion.importFile(file, includingDrawings: true)
        #expect(applied?.isPointerDisplayed == true)
        #expect(companion.isEdited)
        await companion.flush()

        let reopened = makeCompanion()
        let loaded = await reopened.open(pdfAt: url, pageCount: 2)
        // Notes of pages beyond the PDF's page count are kept (NOTES-10).
        #expect(reopened.notes == notes)
        #expect(reopened.drawings == drawings)
        #expect(loaded?.notesMode == .split)
        // The PDF's own reference stays.
        #expect(reopened.entry?.pdf.fileName == "talk.pdf")
    }

    // A file without notes removes the stored notes; without drawings it keeps them when
    // drawings are not imported ("Save drawings" off).
    @Test func importWithoutDrawings() async {
        let companion = makeCompanion()
        await companion.open(pdfAt: locator.add("talk.pdf"), pageCount: 2)
        companion.setNotes(CompanionNotes(format: .rtf, pages: [Data([9])]))
        companion.setDrawings(drawings)
        let file = SlidePilotFile(pdfFileName: "talk.pdf", pdfPageCount: 2, exportedAt: .now)
        _ = companion.importFile(file, includingDrawings: false)
        #expect(companion.notes == nil)
        #expect(companion.drawings == drawings)
    }

    @Test func nothingBeforeTheEntryIsLoaded() {
        let companion = makeCompanion()
        #expect(companion.exportFile() == nil)
        #expect(companion.importFile(SlidePilotFile(pdfFileName: "a.pdf", pdfPageCount: 1, exportedAt: .now), includingDrawings: true) == nil)
    }

    // A PDF that is not open gets the data in the store and shows it when it opens.
    @Test func importIntoAPDFThatIsNotOpen() async throws {
        let store = CompanionStore(directory: directory, locator: locator)
        let url = locator.add("talk.pdf")
        var stored = try #require(await store.open(pdfAt: url, pageCount: 2)).entry
        stored.settings.isNavigatorDisplayed = true
        await store.save(stored)

        let opening = try #require(await store.open(pdfAt: url, pageCount: 2))
        #expect(opening.entry.hasStoredData)
        let notes = CompanionNotes(format: .rtf, pages: [Data([1])])
        let file = SlidePilotFile(pdfFileName: "talk.pdf", pdfPageCount: 2, exportedAt: .now, notes: notes, drawings: drawings)
        let imported = try #require(await store.importFile(file, into: opening.entry, includingDrawings: false))
        #expect(imported.notes == notes)
        #expect(imported.drawings == nil)
        #expect(imported.settings.isNavigatorDisplayed == true)

        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 2)
        #expect(companion.notes == notes)
        #expect(companion.entry?.id == stored.id)
    }

    // An entry deleted while the import waited for confirmation is not written back (SET-07).
    @Test func importIntoADeletedEntryWritesNothing() async throws {
        let store = CompanionStore(directory: directory, locator: locator)
        let url = locator.add("talk.pdf")
        var entry = try #require(await store.open(pdfAt: url, pageCount: 2)).entry
        entry.settings.isNavigatorDisplayed = true
        await store.save(entry)
        await store.delete(entry.id)
        let file = SlidePilotFile(pdfFileName: "talk.pdf", pdfPageCount: 2, exportedAt: .now, notes: CompanionNotes(format: .rtf, pages: [Data([1])]))
        #expect(await store.importFile(file, into: entry, includingDrawings: true) == nil)
        #expect(await store.entries().isEmpty)
    }

    // The stored data overview exports an entry, from the open window when there is one.
    @Test func overviewExportsEntries() async throws {
        let store = CompanionStore(directory: directory, locator: locator)
        let url = locator.add("talk.pdf")
        var entry = try #require(await store.open(pdfAt: url, pageCount: 2)).entry
        entry.notes = CompanionNotes(format: .rtf, pages: [Data([1])])
        await store.save(entry)

        let closed = StoredDataOverview(store: store)
        let date = Date(timeIntervalSince1970: 5)
        #expect(await closed.exportFile(for: entry.id, at: date) == SlidePilotFile(entry: entry, exportedAt: date))
        #expect(await closed.exportFile(for: UUID()) == nil)

        let companion = DocumentCompanion(store: store, saveDelay: .seconds(60))
        await companion.open(pdfAt: url, pageCount: 2)
        let unsaved = CompanionNotes(format: .rtf, pages: [Data([7])])
        companion.setNotes(unsaved)
        let open = StoredDataOverview(store: store) { [companion] }
        #expect(await open.exportFile(for: entry.id)?.notes == unsaved)
    }
}
