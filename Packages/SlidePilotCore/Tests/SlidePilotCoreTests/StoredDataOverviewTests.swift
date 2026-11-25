import Foundation
import SlidePilotCore
import Testing

// SET-07: the stored data overview lists the companion entries and deletes them on request.
@MainActor
@Suite
struct StoredDataOverviewTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "StoredDataOverviewTests-\(UUID().uuidString)")
    let locator = FakeLocator()

    private func makeStore(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> CompanionStore {
        CompanionStore(directory: directory, locator: locator, now: { now })
    }

    private func storedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Opens `name` and stores the given data for it.
    @discardableResult
    private func store(_ name: String, in store: CompanionStore, layout: Bool = true, notes: Bool = false) async throws -> CompanionEntry {
        var entry = try #require(await store.open(pdfAt: locator.add(name), pageCount: 3)).entry
        if layout {
            entry.settings.layout = PresenterLayout(arrangement: .single)
        }
        if notes {
            entry.notes = CompanionNotes(format: .rtf, pages: [Data([1, 2, 3])])
        }
        await store.save(entry)
        return entry
    }

    @Test func kindsListWhatTheEntryHolds() {
        var entry = CompanionEntry(pdf: PDFReference(bookmark: Data(), fileName: "a.pdf", pageCount: 1), lastOpened: .now)
        #expect(entry.storedDataKinds.isEmpty)
        entry.settings.isNavigatorDisplayed = true
        #expect(entry.storedDataKinds == [.settings])
        entry.notes = CompanionNotes(format: .rtf, pages: [Data()])
        // Empty notes are no notes.
        #expect(entry.storedDataKinds == [.settings])
        entry.notes = CompanionNotes(format: .rtf, pages: [Data([1])])
        #expect(entry.storedDataKinds == [.notes, .settings])
    }

    @Test func listsEntriesNewestFirstWithSizeAndKinds() async throws {
        let older = makeStore(now: Date(timeIntervalSince1970: 1_000))
        try await store("old.pdf", in: older)
        let store = makeStore(now: Date(timeIntervalSince1970: 2_000))
        try await self.store("new.pdf", in: store, notes: true)

        let items = await store.storedData()
        #expect(items.map(\.fileName) == ["new.pdf", "old.pdf"])
        #expect(items[0].kinds == [.notes, .settings])
        #expect(items[1].kinds == [.settings])
        #expect(items[1].lastOpened == Date(timeIntervalSince1970: 1_000))
        #expect(items.allSatisfy { $0.byteCount > 0 && $0.isPDFFound })
    }

    // Same-named PDFs show as many folders as tell them apart; a unique name shows none.
    @Test func sameNamedPDFsShowDistinguishingFolders() async throws {
        let store = makeStore()
        try await self.store("2024/week1/slides.pdf", in: store)
        try await self.store("2025/week1/slides.pdf", in: store)
        try await self.store("2025/week2/slides.pdf", in: store)
        try await self.store("2025/handout.pdf", in: store)
        // A PDF that is not found keeps the folders where it was last seen.
        locator.files["2024/week1/slides.pdf"] = nil

        let names = await Set(store.storedData().map(\.displayName))
        #expect(names == ["2024/week1/slides.pdf", "2025/week1/slides.pdf", "week2/slides.pdf", "handout.pdf"])
    }

    @Test func distinguishingFoldersEdgeCases() {
        let folders = StoredDataItem.distinguishingFolders(for: [
            ("a.pdf", ["x", "b"]),
            ("a.pdf", ["b"]),
            // Same path twice and no path known: no folder tells them apart.
            ("c.pdf", ["y"]),
            ("c.pdf", ["y"]),
            ("c.pdf", []),
        ])
        #expect(folders == [["x", "b"], ["b"], ["y"], ["y"], []])
    }

    @Test func marksEntriesWhosePDFIsNotFound() async throws {
        let store = makeStore()
        try await self.store("gone.pdf", in: store)
        try await self.store("here.pdf", in: store)
        locator.files["gone.pdf"] = nil

        let overview = StoredDataOverview(store: store)
        await overview.reload()
        #expect(overview.items?.count == 2)
        #expect(overview.notFoundItems.map(\.fileName) == ["gone.pdf"])
    }

    @Test func deletesSingleEntries() async throws {
        let store = makeStore()
        let entry = try await self.store("a.pdf", in: store)
        try await self.store("b.pdf", in: store)
        let overview = StoredDataOverview(store: store)
        await overview.reload()

        await overview.delete([entry.id])
        #expect(overview.items?.map(\.fileName) == ["b.pdf"])
        #expect(storedFiles().count == 1)
        // Gone for a new store too, i.e. on disk.
        #expect(await makeStore().storedData().map(\.fileName) == ["b.pdf"])
    }

    @Test func deletesOnlyNotFoundEntries() async throws {
        let store = makeStore()
        try await self.store("gone1.pdf", in: store, notes: true)
        try await self.store("gone2.pdf", in: store)
        try await self.store("here.pdf", in: store, notes: true)
        locator.files["gone1.pdf"] = nil
        locator.files["gone2.pdf"] = nil
        let overview = StoredDataOverview(store: store)
        await overview.reload()

        await overview.deleteNotFound()
        #expect(overview.items?.map(\.fileName) == ["here.pdf"])
        #expect(overview.notFoundItems.isEmpty)
        #expect(storedFiles().count == 1)
    }

    // An open document drops the deleted data and does not write it back on its next save.
    @Test func deletingAnOpenDocumentClearsItsCompanion() async throws {
        let store = makeStore()
        let url = locator.add("open.pdf")
        let companion = DocumentCompanion(store: store, saveDelay: .milliseconds(10))
        await companion.open(pdfAt: url, pageCount: 2)
        companion.setNotes(CompanionNotes(format: .rtf, pages: [Data([1])]))
        await companion.flush()
        // An unsaved edit that the delete must not write back.
        companion.setNotes(CompanionNotes(format: .rtf, pages: [Data([2])]))

        let overview = StoredDataOverview(store: store, openCompanions: { [companion] })
        await overview.reload()
        try await overview.delete([#require(overview.items?.first?.id)])

        #expect(companion.notes == nil)
        #expect(companion.settings.isEmpty)
        #expect(!companion.isEdited)
        await companion.flush()
        #expect(storedFiles().isEmpty)
        #expect(overview.items?.isEmpty == true)

        // New notes after the delete are stored again.
        companion.setNotes(CompanionNotes(format: .rtf, pages: [Data([3])]))
        await companion.flush()
        #expect(await store.storedData().map(\.kinds) == [[.notes]])
    }

    // The open document's drawings are cleared with their undo history and not written back
    // (#178). The drawings are wired to the companion as the app does with "Save drawings".
    @Test func deletingAnOpenDocumentClearsItsDrawings() async throws {
        let store = makeStore()
        let companion = DocumentCompanion(store: store, saveDelay: .milliseconds(10))
        await companion.open(pdfAt: locator.add("drawn.pdf"), pageCount: 2)
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.onPagesChange = { companion.setDrawings(CompanionDrawings(pages: $0)) }
        companion.onStoredDataDeleted = { [weak drawings] in drawings?.deleteAll() }
        drawings.startDrawing(onPage: 1)
        drawings.beginLiveStroke(onPage: 1, at: [RelativePoint(x: 0.1, y: 0.2), RelativePoint(x: 0.3, y: 0.4)])
        drawings.commitLiveStroke()
        await companion.flush()
        #expect(await store.storedData().map(\.kinds) == [[.drawings]])
        // A change made after the last save must not be written back either.
        drawings.setBackground(.white, onPage: 0)

        let overview = StoredDataOverview(store: store, openCompanions: { [companion] })
        await overview.reload()
        try await overview.delete([#require(overview.items?.first?.id)])

        #expect(drawings.pages.isEmpty)
        #expect(companion.drawings == nil)
        #expect(!drawings.canUndo(onPage: 0))
        #expect(!drawings.canUndo(onPage: 1))
        #expect(!drawings.undo(onPage: 1))
        await companion.flush()
        #expect(storedFiles().isEmpty)

        // New drawings after the delete are stored again.
        drawings.setBackground(.white, onPage: 1)
        await companion.flush()
        #expect(await store.storedData().map(\.kinds) == [[.drawings]])
    }

    // A document that loaded its entry just before the delete cannot write it back.
    @Test func deletedEntriesAreNeverWrittenAgain() async throws {
        let store = makeStore()
        let entry = try await self.store("loading.pdf", in: store, notes: true)
        await store.delete(entry.id)
        await store.save(entry)
        #expect(storedFiles().isEmpty)
        #expect(await store.storedData().isEmpty)
    }

    @Test func withoutStoreTheListIsEmpty() async {
        let overview = StoredDataOverview(store: nil)
        await overview.reload()
        #expect(overview.items == [])
    }
}
