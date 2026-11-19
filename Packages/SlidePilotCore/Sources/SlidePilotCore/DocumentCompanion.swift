import Foundation
import Observation

/// The companion entry of one open document (NOTES-10, SET-02).
///
/// Loads the entry when the document opens, saves every change shortly afterwards and
/// tracks whether user edits (notes) are still unsaved, for the document-edited indicator
/// (DOC-09). Without a store (previews, tests) nothing is persisted.
///
/// Every write goes through one chain of tasks (`saveChain`): each link waits for the one
/// before it, so writes reach the store in order and `flush()` calls never overtake each other.
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
    /// `true` while the orphaned entry's data is taken over (NOTES-12); notes must not be
    /// edited meanwhile, because the takeover replaces them.
    public private(set) var isTakingOver = false

    @ObservationIgnored private let store: CompanionStore?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var isStored = false
    /// The last link of the save chain.
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// The delayed save that has not started writing yet; cancelling it skips the wait.
    @ObservationIgnored private var delayedSave: Task<Void, Never>?
    /// Counts edits, so a save only clears `isEdited` when no edit came in meanwhile.
    @ObservationIgnored private var editCount = 0
    /// Settings changes made before the entry was loaded; applied to it when it arrives.
    @ObservationIgnored private var changesBeforeLoad: [(inout DocumentSettings) -> Void] = []

    public init(store: CompanionStore?, saveDelay: Duration = .milliseconds(500)) {
        self.store = store
        self.saveDelay = saveDelay
    }

    public var settings: DocumentSettings { entry?.settings ?? DocumentSettings() }

    /// Loads the entry of the PDF at `url` and returns the settings to apply at the end of
    /// opening (SET-02). They include changes made while the entry was loading.
    ///
    /// Called again when the open PDF was renamed or moved: then pending changes are saved
    /// first, only the PDF reference is taken over and `nil` is returned, because the
    /// settings on screen are already current.
    @discardableResult
    public func open(pdfAt url: URL, pageCount: Int) async -> DocumentSettings? {
        guard let store else { return nil }
        if let current = entry {
            await flush()
            guard let opening = await store.open(pdfAt: url, pageCount: pageCount),
                  opening.entry.id == current.id
            else { return nil }
            entry?.pdf = opening.entry.pdf
            entry?.lastOpened = opening.entry.lastOpened
            return nil
        }
        guard let opening = await store.open(pdfAt: url, pageCount: pageCount) else {
            changesBeforeLoad = []
            return nil
        }
        var loaded = opening.entry
        let changes = changesBeforeLoad
        changesBeforeLoad = []
        for change in changes {
            change(&loaded.settings)
        }
        entry = loaded
        isStored = opening.isStored
        // Assigned only on a real change: every assignment of an observed property redraws
        // the views that read it, here the whole document window right after it appeared.
        if orphan != opening.orphan {
            orphan = opening.orphan
        }
        if loaded != opening.entry {
            scheduleSave()
        }
        return loaded.settings
    }

    /// Changes the per-document settings and saves them (SET-02). Changes made before the
    /// entry is loaded are applied to it once it arrives.
    public func updateSettings(_ change: @escaping (inout DocumentSettings) -> Void) {
        guard var entry else {
            if store != nil {
                changesBeforeLoad.append(change)
            }
            return
        }
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
        guard let orphan else { return nil }
        // Cleared before the first suspension, so the alert closes at once.
        self.orphan = nil
        guard let store, entry != nil else { return nil }
        isTakingOver = true
        defer { isTakingOver = false }
        await flush()
        guard let current = entry, let merged = await store.takeOver(orphan.id, for: current) else { return nil }
        entry = merged
        isStored = true
        return merged.settings
    }

    /// Keeps both entries and does not offer this orphan again for this PDF (NOTES-12).
    public func declineOrphan() async {
        guard let orphan else { return }
        self.orphan = nil
        guard let store, let current = entry else { return }
        let updated = await store.decline(orphan.id, for: current)
        // Only the decline is taken over; changes made meanwhile stay.
        entry?.declinedOrphans = updated.declinedOrphans
        isStored = true
    }

    /// The PDF was reloaded (DOC-08): refresh the bookmark, so a recompile that replaced
    /// the file keeps the match (ADR 0013). A reload does not mark the document edited.
    public func pdfDidReload(at url: URL, pageCount: Int) async {
        guard let store, let current = entry else { return }
        let updated = await store.pdfDidChange(current, at: url, pageCount: pageCount, isStored: isStored)
        // Changes made while the store worked win over the snapshot it updated.
        entry?.pdf = updated.pdf
    }

    /// Deletes the stored entry of this document from the stored data overview (SET-07).
    ///
    /// The document continues with empty notes and settings that are not stored, so a later
    /// save does not write the deleted data back; new changes are stored as a new entry.
    /// The settings already applied in the window stay on screen until they change.
    public func deleteStoredData() async {
        guard let store, let current = entry else { return }
        delayedSave?.cancel()
        delayedSave = nil
        entry = CompanionEntry(pdf: current.pdf, lastOpened: current.lastOpened)
        isStored = false
        editCount += 1
        isEdited = false
        // In the save chain, so a save that is already writing finishes before the delete.
        let previous = saveChain
        let link = Task {
            await previous?.value
            await store.delete(current.id)
        }
        saveChain = link
        await link.value
    }

    /// Writes pending changes now, e.g. when the window closes or the app quits or goes to
    /// the background. Returns when they are on disk.
    public func flush() async {
        delayedSave?.cancel()
        delayedSave = nil
        await enqueueSave(after: nil).value
    }

    /// Waits until the changes made so far are saved, without skipping the delay.
    public func waitUntilSaved() async {
        await saveChain?.value
    }

    private func scheduleSave() {
        delayedSave?.cancel()
        let delay = saveDelay
        let wait = Task<Void, Never> {
            try? await Task.sleep(for: delay)
        }
        delayedSave = wait
        _ = enqueueSave(after: wait)
    }

    /// Appends a save to the chain. With `wait`, the save runs after that delay, unless the
    /// delay is cancelled because a newer change or `flush()` saves instead.
    @discardableResult
    private func enqueueSave(after wait: Task<Void, Never>?) -> Task<Void, Never> {
        let previous = saveChain
        // Holds the companion until the save ran, so an edit made while its window
        // closes is still written after the window released it.
        let link = Task { [self] in
            await previous?.value
            if let wait {
                await wait.value
                if wait.isCancelled { return }
            }
            await save()
        }
        saveChain = link
        return link
    }

    private func save() async {
        guard let store, let entry else { return }
        let savedEdits = editCount
        // A PDF without any stored data gets no file, e.g. when its window just closes.
        if entry.hasStoredData || isStored {
            await store.save(entry)
            // Not when the stored data was deleted during the write (SET-07).
            if self.entry?.id == entry.id {
                isStored = true
            }
        }
        if editCount == savedEdits {
            isEdited = false
        }
    }
}
