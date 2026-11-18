import Foundation
import Observation

/// The companion entry of one open document (NOTES-10, SET-02).
///
/// Loads the entry when the document opens, saves every change shortly afterwards and
/// tracks whether user edits (notes) are still unsaved, for the document-edited indicator
/// (DOC-09). Without a store (previews, tests) nothing is persisted.
@MainActor
@Observable
public final class DocumentCompanion {
    /// `nil` until the document's entry was loaded, and when no store is available.
    public private(set) var entry: CompanionEntry?
    /// An entry whose PDF is not found and that looks like this PDF (NOTES-12). The app
    /// offers to take it over; `nil` once accepted or declined.
    public private(set) var orphan: CompanionEntry?
    /// Whether user content (notes) changed and is not saved yet (DOC-09). Settings
    /// changes do not count, like in the old app.
    public private(set) var isEdited = false

    @ObservationIgnored private let store: CompanionStore?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var isStored = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Counts edits, so a save only clears `isEdited` when no edit came in meanwhile.
    @ObservationIgnored private var editCount = 0

    public init(store: CompanionStore?, saveDelay: Duration = .milliseconds(500)) {
        self.store = store
        self.saveDelay = saveDelay
    }

    public var settings: DocumentSettings { entry?.settings ?? DocumentSettings() }

    /// Loads the entry of the PDF at `url`. Returns its settings, which are applied at the
    /// end of opening (SET-02).
    @discardableResult
    public func open(pdfAt url: URL, pageCount: Int) async -> DocumentSettings {
        guard let store, let opening = await store.open(pdfAt: url, pageCount: pageCount) else { return settings }
        entry = opening.entry
        isStored = opening.isStored
        orphan = opening.orphan
        return opening.entry.settings
    }

    /// Changes the per-document settings and saves them (SET-02). Before the entry is
    /// loaded there is nothing to change.
    public func updateSettings(_ change: (inout DocumentSettings) -> Void) {
        guard var entry else { return }
        change(&entry.settings)
        guard entry != self.entry else { return }
        self.entry = entry
        scheduleSave()
    }

    /// The stored text notes (NOTES-10); convert them with `CompanionNotesRTF`.
    public var notes: CompanionNotes? { entry?.notes }

    /// Stores new text notes, marks the document edited and saves shortly afterwards
    /// (NOTES-07, DOC-09). Before the entry is loaded there is nothing to change.
    public func setNotes(_ notes: CompanionNotes) {
        guard entry != nil, entry?.notes != notes else { return }
        entry?.notes = notes
        markEdited()
    }

    /// Records an edit of user content and saves it shortly afterwards. The document shows
    /// as edited until then (DOC-09). `setNotes(_:)` calls it; use it directly only for
    /// edits that are stored another way.
    public func markEdited() {
        isEdited = true
        editCount += 1
        scheduleSave()
    }

    /// Takes over the orphaned entry's data (NOTES-12). Returns the settings to apply.
    public func takeOverOrphan() async -> DocumentSettings? {
        guard let store, let orphan, let entry else { return nil }
        await flush()
        self.orphan = nil
        guard let merged = await store.takeOver(orphan.id, for: entry) else { return nil }
        self.entry = merged
        isStored = true
        return merged.settings
    }

    /// Keeps both entries and does not offer this orphan again for this PDF (NOTES-12).
    public func declineOrphan() async {
        guard let store, let orphan, let entry else { return }
        self.orphan = nil
        self.entry = await store.decline(orphan.id, for: entry)
        isStored = true
    }

    /// The PDF was reloaded (DOC-08): refresh the bookmark, so a recompile that replaced
    /// the file keeps the match (ADR 0013). A reload does not mark the document edited.
    public func pdfDidReload(at url: URL, pageCount: Int) async {
        guard let store, let entry else { return }
        let updated = await store.pdfDidChange(entry, at: url, pageCount: pageCount, isStored: isStored)
        // Changes made while the store worked win over the snapshot it updated.
        if var current = self.entry {
            current.pdf = updated.pdf
            self.entry = current
        }
    }

    /// Writes pending changes now, e.g. when the window closes or the app goes to the background.
    public func flush() async {
        guard let pending = saveTask else { return }
        pending.cancel()
        saveTask = nil
        await pending.value
        await save()
    }

    private func scheduleSave() {
        let previous = saveTask
        previous?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            // A cancelled wait means a newer change or `flush` saves instead.
            await previous?.value
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.save()
        }
    }

    private func save() async {
        guard let store, let entry else { return }
        let savedEdits = editCount
        await store.save(entry)
        isStored = true
        if editCount == savedEdits {
            isEdited = false
        }
    }
}
