import Foundation
import Observation

/// A kind of data that a companion entry can hold, as listed in the stored data overview
/// (SET-07). A new kind (e.g. drawings) adds a case here and its check in
/// `CompanionEntry.storedDataKinds`; the overview lists it without further changes.
public enum StoredDataKind: String, CaseIterable, Sendable, Hashable {
    case notes
    case settings
}

extension CompanionEntry {
    /// What the entry holds, in the order of `StoredDataKind.allCases`.
    public var storedDataKinds: [StoredDataKind] {
        StoredDataKind.allCases.filter { kind in
            switch kind {
            case .notes: !(notes?.isEmpty ?? true)
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
    public var kinds: [StoredDataKind]
    public var lastOpened: Date
    /// Size of the entry's file in bytes.
    public var byteCount: Int64
    /// `false` when the bookmark does not resolve: the PDF was deleted, or it is on a drive
    /// that is not mounted or not downloaded, so nothing is deleted automatically.
    public var isPDFFound: Bool

    public init(id: UUID, fileName: String, kinds: [StoredDataKind], lastOpened: Date, byteCount: Int64, isPDFFound: Bool) {
        self.id = id
        self.fileName = fileName
        self.kinds = kinds
        self.lastOpened = lastOpened
        self.byteCount = byteCount
        self.isPDFFound = isPDFFound
    }
}

extension CompanionStore {
    /// The entries for the stored data overview (SET-07), most recently opened first.
    public func storedData() -> [StoredDataItem] {
        entriesWithFileSizes()
            .map { entry, byteCount in
                StoredDataItem(
                    id: entry.id,
                    fileName: entry.pdf.fileName,
                    kinds: entry.storedDataKinds,
                    lastOpened: entry.lastOpened,
                    byteCount: byteCount,
                    isPDFFound: isPDFFound(entry)
                )
            }
            .sorted { ($0.lastOpened, $0.fileName) > ($1.lastOpened, $1.fileName) }
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

    /// Deletes every entry whose PDF is not found.
    public func deleteNotFound() async {
        await delete(Set(notFoundItems.map(\.id)))
    }
}
