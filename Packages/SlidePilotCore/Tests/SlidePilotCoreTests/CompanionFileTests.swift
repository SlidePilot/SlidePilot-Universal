import Foundation
import SlidePilotCore
import Synchronization
import Testing

@Suite
struct CompanionFileFormatTests {
    private func entry(layout: PresenterLayout? = nil) -> CompanionEntry {
        CompanionEntry(
            pdf: PDFReference(bookmark: Data([1, 2, 3]), fileName: "talk.pdf", pageCount: 12, documentIdentifier: 7),
            lastOpened: Date(timeIntervalSince1970: 1_800_000_000),
            settings: DocumentSettings(layout: layout),
            declinedOrphans: [UUID()]
        )
    }

    // NOTES-10: an entry survives encoding and decoding unchanged.
    @Test func roundTrip() throws {
        var layout = PresenterLayout(arrangement: .tripleRight)
        layout.setLeadingFraction(0.3, in: .tripleRight)
        let original = entry(layout: layout)
        let decoded = try CompanionFileFormat.decode(CompanionFileFormat.encode(original))
        #expect(decoded.entry == original)
        #expect(decoded.formatVersion == CompanionFileFormat.currentVersion)
        #expect(!decoded.isFromNewerVersion)
    }

    @Test func writesTheFormatVersion() throws {
        let json = try JSONSerialization.jsonObject(with: CompanionFileFormat.encode(entry())) as? [String: Any]
        #expect(json?["formatVersion"] as? Int == 1)
    }

    // A file from a later app version is read, flagged and keeps working with unknown fields.
    @Test func readsNewerVersionsWithUnknownFields() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CompanionFileFormat.encode(entry())) as? [String: Any])
        json["formatVersion"] = 99
        var inner = try #require(json["entry"] as? [String: Any])
        inner["futureField"] = ["a": 1]
        json["entry"] = inner
        let decoded = try CompanionFileFormat.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.isFromNewerVersion)
        #expect(decoded.entry.pdf.fileName == "talk.pdf")
    }

    // A damaged setting falls back to "not saved" instead of losing the entry.
    @Test func damagedSettingsFallBackToDefaults() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CompanionFileFormat.encode(entry(layout: .default))) as? [String: Any])
        var inner = try #require(json["entry"] as? [String: Any])
        inner["settings"] = ["layout": "nonsense"]
        inner["lastOpened"] = 42
        json["entry"] = inner
        let decoded = try CompanionFileFormat.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.entry.settings.layout == nil)
        #expect(decoded.entry.lastOpened == .distantPast)
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data(#"{"entry": {}}"#.utf8),
        Data(#"{"formatVersion": 0, "entry": {}}"#.utf8),
        Data(#"{"formatVersion": 1, "entry": {"id": "x"}}"#.utf8),
    ])
    func rejectsDataThatIsNoCompanionFile(_ data: Data) {
        #expect(throws: CompanionFileFormat.DecodingError.unreadable) {
            try CompanionFileFormat.decode(data)
        }
    }

    // SET-03: settings-only entries expire 12 months after the last open.
    @Test func settingsOnlyEntriesExpireAfterTwelveMonths() throws {
        let calendar = Calendar(identifier: .gregorian)
        let item = entry()
        let elevenMonths = try #require(calendar.date(byAdding: .month, value: 11, to: item.lastOpened))
        let twelveMonths = try #require(calendar.date(byAdding: .month, value: 12, to: item.lastOpened))
        #expect(!item.isExpired(at: elevenMonths))
        #expect(item.isExpired(at: twelveMonths))
    }
}

/// A file system in memory: bookmarks are file IDs, files can be renamed, replaced and deleted.
final class FakeLocator: PDFLocator {
    struct File {
        var url: URL
        var isStale = false
    }

    private struct State {
        var files: [String: File] = [:]
        var documentIdentifiers: [URL: Int] = [:]
    }

    private let state = Mutex(State())

    var files: [String: File] {
        get { state.withLock { $0.files } }
        set { state.withLock { $0.files = newValue } }
    }

    var documentIdentifiers: [URL: Int] {
        get { state.withLock { $0.documentIdentifiers } }
        set { state.withLock { $0.documentIdentifiers = newValue } }
    }

    @discardableResult
    func add(_ name: String, id: String? = nil) -> URL {
        let url = URL(filePath: "/decks/\(name)")
        files[id ?? name] = File(url: url)
        return url
    }

    func bookmark(for url: URL) throws -> Data {
        try state.withLock { state in
            guard let id = state.files.first(where: { $0.value.url == url })?.key else { throw CocoaError(.fileNoSuchFile) }
            state.files[id]?.isStale = false
            return Data(id.utf8)
        }
    }

    func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        files[String(decoding: bookmark, as: UTF8.self)].map { ResolvedBookmark(url: $0.url, isStale: $0.isStale) }
    }

    func isSameFile(_ first: URL, _ second: URL) -> Bool { first == second }

    func documentIdentifier(of url: URL) -> Int? { documentIdentifiers[url] }
}

@Suite
struct CompanionStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "CompanionStoreTests-\(UUID().uuidString)")
    let locator = FakeLocator()

    private func makeStore(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> CompanionStore {
        CompanionStore(directory: directory, locator: locator, now: { now })
    }

    private func storedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func saveLayout(_ store: CompanionStore, for url: URL, pageCount: Int = 10) async throws -> CompanionEntry {
        var entry = try #require(await store.open(pdfAt: url, pageCount: pageCount)).entry
        entry.settings.layout = PresenterLayout(arrangement: .single)
        await store.save(entry)
        return entry
    }

    // A PDF without stored data writes nothing until something is saved.
    @Test func openingANewPDFWritesNothing() async throws {
        let store = makeStore()
        let opening = try #require(await store.open(pdfAt: locator.add("talk.pdf"), pageCount: 10))
        #expect(!opening.isStored)
        #expect(opening.entry.pdf.fileName == "talk.pdf")
        #expect(storedFiles().isEmpty)
    }

    // SET-02: saved settings are found again by a new store (next launch).
    @Test func savedSettingsAreFoundAfterRelaunch() async throws {
        let url = locator.add("talk.pdf")
        let saved = try await saveLayout(makeStore(), for: url)
        #expect(storedFiles().count == 1)
        let opening = try #require(await makeStore().open(pdfAt: url, pageCount: 10))
        #expect(opening.isStored)
        #expect(opening.entry.id == saved.id)
        #expect(opening.entry.settings.layout?.arrangement == .single)
    }

    // ADR 0012: the bookmark follows a rename or move; name and page count are updated.
    @Test func renamedPDFKeepsItsEntry() async throws {
        let url = locator.add("talk.pdf")
        let saved = try await saveLayout(makeStore(), for: url)
        locator.files["talk.pdf"]?.url = URL(filePath: "/elsewhere/renamed.pdf")
        let opening = try #require(await makeStore().open(pdfAt: URL(filePath: "/elsewhere/renamed.pdf"), pageCount: 11))
        #expect(opening.entry.id == saved.id)
        #expect(opening.entry.pdf.fileName == "renamed.pdf")
        #expect(opening.entry.pdf.pageCount == 11)
    }

    // ADR 0013: a stale bookmark (file replaced by a recompile) is refreshed on open.
    @Test func staleBookmarkIsRefreshedOnOpen() async throws {
        let url = locator.add("talk.pdf")
        _ = try await saveLayout(makeStore(), for: url)
        locator.files["talk.pdf"]?.isStale = true
        _ = await makeStore().open(pdfAt: url, pageCount: 10)
        #expect(locator.files["talk.pdf"]?.isStale == false)
    }

    // iPadOS: the document identifier matches without resolving bookmarks.
    @Test func documentIdentifierMatches() async throws {
        let url = locator.add("talk.pdf")
        locator.documentIdentifiers[url] = 42
        let saved = try await saveLayout(makeStore(), for: url)
        let moved = URL(filePath: "/provider/talk.pdf")
        locator.documentIdentifiers[moved] = 42
        locator.files["talk.pdf"] = nil
        locator.add("talk.pdf", id: "new")
        locator.files["new"]?.url = moved
        let opening = try #require(await makeStore().open(pdfAt: moved, pageCount: 10))
        #expect(opening.entry.id == saved.id)
    }

    // SET-03 and DEF-10: the expiry counts from the last open, not from the last save.
    @Test func expiryCountsFromLastOpen() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let url = locator.add("talk.pdf")
        _ = try await saveLayout(makeStore(now: start), for: url)
        let elevenMonths = try #require(calendar.date(byAdding: .month, value: 11, to: start))
        _ = await makeStore(now: elevenMonths).open(pdfAt: url, pageCount: 10)
        let later = try #require(calendar.date(byAdding: .month, value: 13, to: start))
        #expect(await makeStore(now: later).removeExpiredEntries().isEmpty)
        let muchLater = try #require(calendar.date(byAdding: .month, value: 24, to: start))
        #expect(await makeStore(now: muchLater).removeExpiredEntries().count == 1)
        #expect(storedFiles().isEmpty)
    }

    // A file from a later app version is used but never overwritten or expired.
    @Test func newerVersionFilesAreNotOverwritten() async throws {
        let url = locator.add("talk.pdf")
        let saved = try await saveLayout(makeStore(), for: url)
        let file = try #require(storedFiles().first)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["formatVersion"] = 2
        let newer = try JSONSerialization.data(withJSONObject: json)
        try newer.write(to: file)

        let store = makeStore(now: .distantFuture)
        var entry = try #require(await store.open(pdfAt: url, pageCount: 10)).entry
        #expect(entry.id == saved.id)
        entry.settings.layout = .default
        await store.save(entry)
        #expect(await store.removeExpiredEntries().isEmpty)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test func ignoresUnreadableFiles() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: directory.appending(path: "\(UUID().uuidString).json"))
        #expect(await makeStore().entries().isEmpty)
    }

    // NOTES-12: one not-found entry with the same name and page count is offered.
    @Test func offersASingleMatchingOrphan() async throws {
        let original = locator.add("talk.pdf")
        let saved = try await saveLayout(makeStore(), for: original)
        locator.files["talk.pdf"] = nil
        let copy = locator.add("talk.pdf", id: "copy")
        let opening = try #require(await makeStore().open(pdfAt: copy, pageCount: 10))
        #expect(opening.orphan?.id == saved.id)
    }

    @Test func noOrphanForAnotherPageCountOrAFoundPDF() async throws {
        let original = locator.add("talk.pdf")
        _ = try await saveLayout(makeStore(), for: original)
        let copy = URL(filePath: "/copies/talk.pdf")
        locator.files["copy"] = FakeLocator.File(url: copy)
        // The original still exists: a copy is not an orphan case.
        #expect(try #require(await makeStore().open(pdfAt: copy, pageCount: 10)).orphan == nil)
        locator.files["talk.pdf"] = nil
        #expect(try #require(await makeStore().open(pdfAt: copy, pageCount: 9)).orphan == nil)
    }

    // NOTES-12: with several candidates the app does not guess.
    @Test func noOrphanWhenSeveralMatch() async throws {
        _ = try await saveLayout(makeStore(), for: locator.add("talk.pdf", id: "a"))
        locator.files["a"]?.url = URL(filePath: "/a/talk.pdf")
        _ = try await saveLayout(makeStore(), for: locator.add("talk.pdf", id: "b"))
        locator.files["a"] = nil
        locator.files["b"] = nil
        let copy = locator.add("talk.pdf", id: "copy")
        #expect(try #require(await makeStore().open(pdfAt: copy, pageCount: 10)).orphan == nil)
    }

    // NOTES-12: taking over moves the data to the opened PDF.
    @Test func takeOverMovesTheEntry() async throws {
        let saved = try await saveLayout(makeStore(), for: locator.add("talk.pdf"))
        locator.files["talk.pdf"] = nil
        let copy = locator.add("talk.pdf", id: "copy")
        let store = makeStore()
        let opening = try #require(await store.open(pdfAt: copy, pageCount: 10))
        let merged = try #require(await store.takeOver(saved.id, for: opening.entry))
        #expect(merged.id == saved.id)
        #expect(merged.settings.layout?.arrangement == .single)
        #expect(storedFiles().count == 1)
        let reopened = try #require(await makeStore().open(pdfAt: copy, pageCount: 10))
        #expect(reopened.entry.id == saved.id)
        #expect(reopened.orphan == nil)
    }

    // NOTES-12: declining keeps both entries and is remembered for this pair.
    @Test func declineIsRemembered() async throws {
        let saved = try await saveLayout(makeStore(), for: locator.add("talk.pdf"))
        locator.files["talk.pdf"] = nil
        let copy = locator.add("talk.pdf", id: "copy")
        let store = makeStore()
        let opening = try #require(await store.open(pdfAt: copy, pageCount: 10))
        _ = await store.decline(saved.id, for: opening.entry)
        #expect(storedFiles().count == 2)
        #expect(try #require(await makeStore().open(pdfAt: copy, pageCount: 10)).orphan == nil)
    }

    // ADR 0013: after a reload the bookmark is created again.
    @Test func reloadRefreshesTheBookmark() async throws {
        let url = locator.add("talk.pdf")
        let store = makeStore()
        let saved = try await saveLayout(store, for: url)
        locator.files["talk.pdf"]?.isStale = true
        let updated = await store.pdfDidChange(saved, at: url, pageCount: 4, isStored: true)
        #expect(locator.files["talk.pdf"]?.isStale == false)
        #expect(updated.pdf.pageCount == 4)
        #expect(await makeStore().entries().first?.pdf.pageCount == 4)
    }
}

/// The real bookmarks in a temporary folder (ADR 0012, #25 matching checks).
@Suite
struct FileBookmarkLocatorTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "BookmarkTests-\(UUID().uuidString)")
    let locator = FileBookmarkLocator()

    private func makePDF(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("%PDF-1.4\n%%EOF\n".utf8).write(to: url)
        return url
    }

    @Test func followsARename() throws {
        let url = try makePDF("talk.pdf")
        let bookmark = try locator.bookmark(for: url)
        let renamed = folder.appending(path: "renamed.pdf")
        try FileManager.default.moveItem(at: url, to: renamed)
        let resolved = try #require(locator.resolve(bookmark))
        #expect(locator.isSameFile(resolved.url, renamed))
    }

    @Test func followsAMoveToAnotherFolder() throws {
        let url = try makePDF("talk.pdf")
        let bookmark = try locator.bookmark(for: url)
        let subfolder = folder.appending(path: "sub")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let moved = subfolder.appending(path: "talk.pdf")
        try FileManager.default.moveItem(at: url, to: moved)
        let resolved = try #require(locator.resolve(bookmark))
        #expect(locator.isSameFile(resolved.url, moved))
    }

    // A recompile with an atomic save replaces the file; the bookmark still finds the path.
    @Test func findsAnAtomicallyReplacedFile() throws {
        let url = try makePDF("talk.pdf")
        let bookmark = try locator.bookmark(for: url)
        try Data("%PDF-1.4\nnew\n%%EOF\n".utf8).write(to: url, options: .atomic)
        let resolved = try #require(locator.resolve(bookmark))
        #expect(locator.isSameFile(resolved.url, url))
    }

    @Test func deletedFileIsNotFound() throws {
        let url = try makePDF("talk.pdf")
        let bookmark = try locator.bookmark(for: url)
        try FileManager.default.removeItem(at: url)
        #expect(locator.resolve(bookmark) == nil)
    }

    @Test func otherFileIsNotTheSame() throws {
        let first = try makePDF("a.pdf")
        let second = try makePDF("b.pdf")
        #expect(!locator.isSameFile(first, second))
        #expect(locator.isSameFile(first, folder.appending(path: "./a.pdf")))
    }
}

@MainActor
@Suite
struct DocumentCompanionTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "DocumentCompanionTests-\(UUID().uuidString)")
    let locator = FakeLocator()

    private func makeCompanion() -> DocumentCompanion {
        DocumentCompanion(store: CompanionStore(directory: directory, locator: locator), saveDelay: .milliseconds(10))
    }

    // SET-02: a settings change is saved and loaded on the next open.
    @Test func settingsChangeIsSavedAndLoaded() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 3)
        companion.updateSettings { $0.layout = PresenterLayout(arrangement: .single) }
        #expect(!companion.isEdited)
        await companion.flush()
        let settings = await makeCompanion().open(pdfAt: url, pageCount: 3)
        #expect(settings?.layout?.arrangement == .single)
    }

    // DOC-09: an edit marks the document edited until it is saved.
    @Test func editIsShownUntilSaved() async {
        let companion = makeCompanion()
        await companion.open(pdfAt: locator.add("talk.pdf"), pageCount: 3)
        companion.markEdited()
        #expect(companion.isEdited)
        await companion.flush()
        #expect(!companion.isEdited)
    }

    // The delayed save also runs without a flush.
    @Test func savesAfterTheDelay() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 3)
        companion.markEdited()
        await companion.waitUntilSaved()
        #expect(!companion.isEdited)
    }

    // Closing a PDF without stored data writes nothing.
    @Test func flushWithoutDataWritesNothing() async {
        let companion = makeCompanion()
        await companion.open(pdfAt: locator.add("talk.pdf"), pageCount: 3)
        await companion.flush()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        #expect(files.isEmpty)
    }

    // LAY-05: a change made while the entry loads is kept and saved.
    @Test func changeBeforeLoadIsKept() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        companion.updateSettings { $0.layout = PresenterLayout(arrangement: .single) }
        let settings = await companion.open(pdfAt: url, pageCount: 3)
        #expect(settings?.layout?.arrangement == .single)
        await companion.flush()
        #expect(await makeCompanion().open(pdfAt: url, pageCount: 3)?.layout?.arrangement == .single)
    }

    // A rename while the document is open re-opens it: unsaved changes are kept.
    @Test func reopenAfterRenameKeepsUnsavedChanges() async {
        let url = locator.add("talk.pdf")
        let companion = DocumentCompanion(store: CompanionStore(directory: directory, locator: locator), saveDelay: .seconds(60))
        await companion.open(pdfAt: url, pageCount: 3)
        companion.updateSettings { $0.layout = PresenterLayout(arrangement: .single) }
        let renamed = URL(filePath: "/decks/renamed.pdf")
        locator.files["talk.pdf"]?.url = renamed
        #expect(await companion.open(pdfAt: renamed, pageCount: 3) == nil)
        #expect(companion.settings.layout?.arrangement == .single)
        #expect(companion.entry?.pdf.fileName == "renamed.pdf")
        await companion.flush()
        #expect(await makeCompanion().open(pdfAt: renamed, pageCount: 3)?.layout?.arrangement == .single)
    }

    @Test func withoutStoreNothingIsLoaded() async {
        let companion = DocumentCompanion(store: nil)
        let settings = await companion.open(pdfAt: URL(filePath: "/x.pdf"), pageCount: 1)
        #expect(settings == nil)
        companion.updateSettings { $0.layout = .default }
        #expect(companion.entry == nil)
    }

    // NOTES-12 through the document: accepting applies the orphan's settings.
    @Test func acceptingTheOrphanReturnsItsSettings() async {
        let original = locator.add("talk.pdf")
        let first = makeCompanion()
        await first.open(pdfAt: original, pageCount: 3)
        first.updateSettings { $0.layout = PresenterLayout(arrangement: .tripleRight) }
        await first.flush()
        locator.files["talk.pdf"] = nil
        let copy = locator.add("talk.pdf", id: "copy")
        let second = makeCompanion()
        await second.open(pdfAt: copy, pageCount: 3)
        #expect(second.orphan != nil)
        let settings = await second.takeOverOrphan()
        #expect(settings?.layout?.arrangement == .tripleRight)
        #expect(second.orphan == nil)
    }
}

@MainActor
@Suite
struct PerDocumentLayoutTests {
    // LAY-05: a user change updates the last-used layout and the document's layout.
    @Test func changeUpdatesBoth() {
        let store = InMemoryPresenterLayoutStore()
        let model = PresenterLayoutModel(store: store)
        var reported: PresenterLayout?
        model.onChange = { reported = $0 }
        model.setArrangement(.single)
        #expect(store.layout?.arrangement == .single)
        #expect(reported?.arrangement == .single)
    }

    // LAY-05: loading a document's layout is not a change.
    @Test func applyingTheStoredLayoutIsNoChange() {
        let store = InMemoryPresenterLayoutStore(layout: .default)
        let model = PresenterLayoutModel(store: store)
        var reported = false
        model.onChange = { _ in reported = true }
        model.applyStoredLayout(PresenterLayout(arrangement: .single))
        #expect(model.arrangement == .single)
        #expect(store.layout == .default)
        #expect(!reported)
    }
}

@Suite
struct CompanionNotesTests {
    private func entry(notes: CompanionNotes?) -> CompanionEntry {
        CompanionEntry(
            pdf: PDFReference(bookmark: Data([1]), fileName: "talk.pdf", pageCount: 2),
            lastOpened: Date(timeIntervalSince1970: 0),
            notes: notes
        )
    }

    // NOTES-10: notes survive encoding and decoding, including empty pages.
    @Test func notesRoundTrip() throws {
        let notes = CompanionNotes(format: .rtf, pages: [Data("{\\rtf1 a}".utf8), Data()])
        let decoded = try CompanionFileFormat.decode(CompanionFileFormat.encode(entry(notes: notes)))
        #expect(decoded.entry.notes == notes)
    }

    // A format added by a later version is kept, not dropped.
    @Test func unknownNotesFormatIsKept() throws {
        let notes = CompanionNotes(format: CompanionNotes.Format(rawValue: "future"), pages: [Data([1])])
        let decoded = try CompanionFileFormat.decode(CompanionFileFormat.encode(entry(notes: notes)))
        #expect(decoded.entry.notes?.format.rawValue == "future")
    }

    // ADR 0012: entries with notes never expire; empty notes do not count.
    @Test func entriesWithNotesDoNotExpire() {
        #expect(!entry(notes: CompanionNotes(format: .rtf, pages: [Data([1])])).isExpired(at: .distantFuture))
        #expect(entry(notes: CompanionNotes(format: .rtf, pages: [Data()])).isExpired(at: .distantFuture))
    }

    // Damaged notes make the file unreadable instead of being dropped by the next save.
    @Test func damagedNotesAreNotDropped() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CompanionFileFormat.encode(entry(notes: nil))) as? [String: Any])
        var inner = try #require(json["entry"] as? [String: Any])
        inner["notes"] = ["pages": 3]
        json["entry"] = inner
        #expect(throws: CompanionFileFormat.DecodingError.unreadable) {
            try CompanionFileFormat.decode(JSONSerialization.data(withJSONObject: json))
        }
    }

    // NOTES-07, DOC-09: setting notes marks the document edited until they are saved.
    @MainActor
    @Test func setNotesSavesAndMarksEdited() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CompanionNotesTests-\(UUID().uuidString)")
        let locator = FakeLocator()
        let url = locator.add("talk.pdf")
        let companion = DocumentCompanion(store: CompanionStore(directory: directory, locator: locator), saveDelay: .milliseconds(10))
        await companion.open(pdfAt: url, pageCount: 2)
        let notes = CompanionNotes(format: .rtf, pages: [Data([1])])
        companion.setNotes(notes)
        #expect(companion.isEdited)
        await companion.flush()
        #expect(!companion.isEdited)
        let reopened = DocumentCompanion(store: CompanionStore(directory: directory, locator: locator))
        await reopened.open(pdfAt: url, pageCount: 2)
        #expect(reopened.notes == notes)
    }
}
