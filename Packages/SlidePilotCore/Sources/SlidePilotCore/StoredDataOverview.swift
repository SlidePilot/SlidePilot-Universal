import Foundation
import Observation

/// A kind of data that a companion entry can hold, as listed in the stored data overview
/// (SET-07) and for a `.slidepilot` file (NOTES-11). A new kind adds a case here and its check in
/// `CompanionEntry.storedDataKinds` (and, if it is user content, in
/// `CompanionEntry.holdsUserContent`, so it does not expire); the overview lists it without
/// further changes.
public enum StoredDataKind: String, CaseIterable, Sendable, Hashable {
    case notes
    case drawings
    case settings
}

extension CompanionEntry {
    /// What the entry holds, in the order of `StoredDataKind.allCases`.
    public var storedDataKinds: [StoredDataKind] {
        StoredDataKind.allCases.filter { kind in
            switch kind {
            case .notes: !(notes?.isEmpty ?? true)
            case .drawings: !(drawings?.isEmpty ?? true)
            case .settings: !settings.isEmpty
            }
        }
    }
}

/// One row of the stored data overview (SET-07): a companion entry and whether its PDF is found.
public struct StoredDataItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// The PDF's file name when it was last opened.
    public var fileName: String
    /// The last folders of the PDF's path, as many as tell it apart from other entries with
    /// the same file name (outermost first); empty when the name is unique.
    public var distinguishingFolders: [String]
    public var kinds: [StoredDataKind]
    public var lastOpened: Date
    /// Size of the entry's file in bytes.
    public var byteCount: Int64
    /// `false` when the bookmark does not resolve: the PDF was deleted, or it is on a drive
    /// that is not mounted or not downloaded, so nothing is deleted automatically.
    public var isPDFFound: Bool

    public init(id: UUID, fileName: String, distinguishingFolders: [String] = [], kinds: [StoredDataKind], lastOpened: Date, byteCount: Int64, isPDFFound: Bool) {
        self.id = id
        self.fileName = fileName
        self.distinguishingFolders = distinguishingFolders
        self.kinds = kinds
        self.lastOpened = lastOpened
        self.byteCount = byteCount
        self.isPDFFound = isPDFFound
    }
}

extension CompanionStore {
    /// The entries for the stored data overview (SET-07), most recently opened first.
    public func storedData() -> [StoredDataItem] {
        let rows = entriesWithFileSizes().map { entry, byteCount in
            (entry: entry, byteCount: byteCount, location: pdfLocation(of: entry))
        }
        let folders = StoredDataItem.distinguishingFolders(
            for: rows.map { ($0.entry.pdf.fileName, $0.location.url?.deletingLastPathComponent().pathComponents.filter { $0 != "/" } ?? []) }
        )
        return zip(rows, folders)
            .map { row, folders in
                StoredDataItem(
                    id: row.entry.id,
                    fileName: row.entry.pdf.fileName,
                    distinguishingFolders: folders,
                    kinds: row.entry.storedDataKinds,
                    lastOpened: row.entry.lastOpened,
                    byteCount: row.byteCount,
                    isPDFFound: row.location.isFound
                )
            }
            .sorted { ($0.lastOpened, $0.fileName) > ($1.lastOpened, $1.fileName) }
    }
}

extension StoredDataItem {
    /// For each file (name and folders of its path, outermost first), the fewest last folders
    /// that tell it apart from every other file with the same name. Unique names get none; a
    /// file that no folder tells apart (same path, or no path known) gets all of its folders.
    public static func distinguishingFolders(for files: [(name: String, folders: [String])]) -> [[String]] {
        files.indices.map { index in
            let file = files[index]
            let others = files.indices.filter { $0 != index && files[$0].name == file.name }.map { files[$0].folders }
            guard !others.isEmpty else { return [] }
            for count in stride(from: 1, through: file.folders.count, by: 1) {
                let suffix = file.folders.suffix(count)
                if !others.contains(where: { $0.suffix(count) == suffix }) {
                    return Array(suffix)
                }
            }
            return file.folders
        }
    }

    /// The file name with the distinguishing folders in front, e.g. "Week 2/slides.pdf".
    public var displayName: String {
        (distinguishingFolders + [fileName]).joined(separator: "/")
    }
}

/// The stored data overview in Settings (SET-07): lists the companion entries and deletes
/// them on request. Nothing is deleted automatically.
///
/// Entries of open documents are deleted through their `DocumentCompanion`, so the open
/// window drops its notes and settings too instead of writing them back on its next save.
@MainActor
@Observable
public final class StoredDataOverview {
    /// `nil` until loaded.
    public private(set) var items: [StoredDataItem]?

    @ObservationIgnored private let store: CompanionStore?
    @ObservationIgnored private let openCompanions: @MainActor () -> [DocumentCompanion]

    /// - Parameter openCompanions: the companions of the open documents.
    public init(store: CompanionStore?, openCompanions: @escaping @MainActor () -> [DocumentCompanion] = { [] }) {
        self.store = store
        self.openCompanions = openCompanions
    }

    /// The entries whose PDF is not found.
    public var notFoundItems: [StoredDataItem] { items?.filter { !$0.isPDFFound } ?? [] }

    /// Reads the entries again.
    public func reload() async {
        let loaded = await store?.storedData() ?? []
        if loaded != items {
            items = loaded
        }
    }

    /// Deletes the entries with these IDs, then reloads.
    public func delete(_ ids: Set<UUID>) async {
        guard let store, !ids.isEmpty else { return }
        // Shown as gone at once; the reload confirms it.
        items?.removeAll { ids.contains($0.id) }
        var remaining = ids
        for companion in openCompanions() {
            guard let id = companion.entry?.id, remaining.contains(id) else { continue }
            await companion.deleteStoredData()
            remaining.remove(id)
        }
        for id in remaining {
            await store.delete(id)
        }
        await reload()
    }

    /// The data of an entry as a `.slidepilot` file (NOTES-11). An open document's entry is
    /// taken from its window, which may hold changes that are not saved yet.
    public func exportFile(for id: UUID, at date: Date = Date()) async -> SlidePilotFile? {
        if let companion = openCompanions().first(where: { $0.entry?.id == id }) {
            return companion.exportFile(at: date)
        }
        return await store?.entry(withID: id).map { SlidePilotFile(entry: $0, exportedAt: date) }
    }

    /// Deletes every entry whose PDF is not found.
    public func deleteNotFound() async {
        await delete(Set(notFoundItems.map(\.id)))
    }
}
