import Foundation

/// The companion entries in the app container: one JSON file per PDF (NOTES-10, ADR 0012).
///
/// An actor, because every call reads or writes files and resolves bookmarks. One store
/// serves all document windows, so their writes never interleave.
public actor CompanionStore {
    /// What the store knows about a PDF that is being opened.
    public struct Opening: Sendable, Equatable {
        /// The PDF's entry: the stored one, or a new one that is written on its first change.
        public var entry: CompanionEntry
        /// Whether `entry` is already on disk.
        public var isStored: Bool
        /// An entry whose PDF is not found and that looks like this PDF (NOTES-12).
        public var orphan: CompanionEntry?
    }

    private struct Stored {
        var entry: CompanionEntry
        /// Written by a later app version: used, but never overwritten.
        var isReadOnly: Bool
    }

    private let directory: URL
    private let locator: any PDFLocator
    private let now: @Sendable () -> Date
    /// Loaded from disk on first use. The store is the only writer of its directory.
    private var cache: [UUID: Stored]?
    /// Entries deleted in this run. They are never written again, so a document that still
    /// holds a deleted entry (it was loading or closing during the delete) cannot bring the
    /// deleted data back (SET-07).
    private var deletedIDs: Set<UUID> = []

    public init(directory: URL, locator: any PDFLocator = FileBookmarkLocator(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.locator = locator
        self.now = now
    }

    /// The app's store in Application Support.
    public static func appContainer() throws -> CompanionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return CompanionStore(directory: support.appending(path: "Documents", directoryHint: .isDirectory))
    }

    // MARK: - Opening a PDF

    /// Finds the entry of the PDF at `url` and records the open (SET-03).
    ///
    /// The match uses the document identifier where the system has one, then the stored
    /// bookmarks, so renames and moves keep the match. A stale bookmark (the PDF was
    /// replaced, e.g. by a recompile) is refreshed. `nil` when no bookmark can be created
    /// for the PDF; the document then opens without stored data.
    public func open(pdfAt url: URL, pageCount: Int) -> Opening? {
        let entries = storedEntries()
        let documentIdentifier = locator.documentIdentifier(of: url)
        // Filled while scanning the bookmarks; `nil` after a document-identifier match.
        var notFound: [CompanionEntry]?
        var match: (stored: Stored, isStale: Bool)?

        if let documentIdentifier, let stored = entries.first(where: { $0.entry.pdf.documentIdentifier == documentIdentifier }) {
            match = (stored, locator.resolve(stored.entry.pdf.bookmark)?.isStale ?? true)
        } else {
            notFound = []
            for stored in entries {
                guard let resolved = locator.resolve(stored.entry.pdf.bookmark) else {
                    notFound?.append(stored.entry)
                    continue
                }
                if match == nil, locator.isSameFile(resolved.url, url) {
                    match = (stored, resolved.isStale)
                }
            }
        }

        if let match {
            var entry = match.stored.entry
            if match.isStale, let bookmark = try? locator.bookmark(for: url) {
                entry.pdf.bookmark = bookmark
            }
            entry.pdf.fileName = url.lastPathComponent
            entry.pdf.pageCount = pageCount
            entry.pdf.documentIdentifier = documentIdentifier ?? entry.pdf.documentIdentifier
            entry.lastOpened = now()
            write(entry)
            // NOTES-12 applies only to PDFs without stored data.
            let orphan = entry.hasStoredData ? nil : orphan(among: notFoundEntries(in: entries, scanned: notFound), for: entry)
            return Opening(entry: entry, isStored: true, orphan: orphan)
        }

        let bookmark: Data
        do {
            bookmark = try locator.bookmark(for: url)
        } catch {
            companionLog.error("No bookmark for the opened PDF, its data is not stored: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let entry = CompanionEntry(
            pdf: PDFReference(bookmark: bookmark, fileName: url.lastPathComponent, pageCount: pageCount, documentIdentifier: documentIdentifier),
            lastOpened: now()
        )
        return Opening(entry: entry, isStored: false, orphan: orphan(among: notFoundEntries(in: entries, scanned: notFound), for: entry))
    }

    /// Moves the orphaned entry's data to `entry`'s PDF (NOTES-12). The orphan keeps its ID,
    /// `entry` is removed. Returns the entry that now belongs to the PDF.
    public func takeOver(_ orphanID: UUID, for entry: CompanionEntry) -> CompanionEntry? {
        guard var orphan = cache?[orphanID]?.entry else { return nil }
        orphan.pdf = entry.pdf
        orphan.lastOpened = now()
        if cache?[entry.id] != nil {
            delete(entry.id)
        }
        write(orphan)
        return orphan
    }

    /// Remembers that the orphan should not be offered to `entry`'s PDF again (NOTES-12).
    public func decline(_ orphanID: UUID, for entry: CompanionEntry) -> CompanionEntry {
        var entry = entry
        entry.declinedOrphans.insert(orphanID)
        write(entry)
        return entry
    }

    /// Creates the bookmark of `entry`'s PDF again after a reload replaced the file
    /// (DOC-08, ADR 0013), and stores the new page count. Returns the updated entry.
    public func pdfDidChange(_ entry: CompanionEntry, at url: URL, pageCount: Int, isStored: Bool) -> CompanionEntry {
        var entry = entry
        if let bookmark = try? locator.bookmark(for: url) {
            entry.pdf.bookmark = bookmark
        }
        entry.pdf.pageCount = pageCount
        if isStored {
            write(entry)
        }
        return entry
    }

    // MARK: - Saving

    /// Writes `entry`. Entries from a later app version are not overwritten.
    public func save(_ entry: CompanionEntry) {
        write(entry)
    }

    public func entries() -> [CompanionEntry] {
        storedEntries().map(\.entry)
    }

    /// Imports a `.slidepilot` file into the entry of a PDF that is not open (NOTES-11) and
    /// stores it. `entry` comes from `open(pdfAt:pageCount:)`. Returns the stored entry.
    public func importFile(_ file: SlidePilotFile, into entry: CompanionEntry, includingDrawings: Bool) -> CompanionEntry {
        var entry = cache?[entry.id]?.entry ?? entry
        entry.importFile(file, includingDrawings: includingDrawings)
        write(entry)
        return entry
    }

    /// The stored entry with this ID, e.g. to export it (NOTES-11).
    public func entry(withID id: UUID) -> CompanionEntry? {
        _ = storedEntries()
        return cache?[id]?.entry
    }

    /// The entries with the size of their files, for the stored data overview (SET-07).
    func entriesWithFileSizes() -> [(entry: CompanionEntry, byteCount: Int64)] {
        storedEntries().map { stored in
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(of: stored.entry.id).path(percentEncoded: false))[.size] as? NSNumber)?.int64Value
            return (stored.entry, size ?? 0)
        }
    }

    /// Where the entry's PDF is now, or where it was last seen when it is not found.
    func pdfLocation(of entry: CompanionEntry) -> (url: URL?, isFound: Bool) {
        if let resolved = locator.resolve(entry.pdf.bookmark) {
            return (resolved.url, true)
        }
        return (locator.lastKnownURL(of: entry.pdf.bookmark), false)
    }

    public func delete(_ id: UUID) {
        _ = storedEntries()
        deletedIDs.insert(id)
        cache?[id] = nil
        try? FileManager.default.removeItem(at: fileURL(of: id))
    }

    /// Removes the drawings of every entry, when "Save drawings" is turned off (DRAW-06).
    /// Entries from a later app version are left alone. Returns the IDs of the changed entries.
    @discardableResult
    public func removeAllDrawings() -> [UUID] {
        var changed: [UUID] = []
        for stored in storedEntries() where !stored.isReadOnly && stored.entry.drawings != nil {
            var entry = stored.entry
            entry.drawings = nil
            write(entry)
            changed.append(entry.id)
        }
        return changed
    }

    /// Removes settings-only entries that were not opened for 12 months (SET-03). Runs at
    /// launch. Returns the IDs of the removed entries.
    @discardableResult
    public func removeExpiredEntries() -> [UUID] {
        let date = now()
        let expired = storedEntries().filter { !$0.isReadOnly && $0.entry.isExpired(at: date) }.map(\.entry.id)
        for id in expired {
            delete(id)
        }
        return expired
    }

    // MARK: - Files

    private func storedEntries() -> [Stored] {
        if let cache { return Array(cache.values) }
        var loaded: [UUID: Stored] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == CompanionFileFormat.fileExtension {
            guard let data = try? Data(contentsOf: file),
                  let decoded = try? CompanionFileFormat.decode(data),
                  file.deletingPathExtension().lastPathComponent == decoded.entry.id.uuidString
            else { continue }
            loaded[decoded.entry.id] = Stored(entry: decoded.entry, isReadOnly: decoded.isFromNewerVersion)
        }
        cache = loaded
        return Array(loaded.values)
    }

    private func write(_ entry: CompanionEntry) {
        _ = storedEntries()
        guard !deletedIDs.contains(entry.id) else { return }
        if cache?[entry.id]?.isReadOnly == true {
            cache?[entry.id]?.entry = entry
            return
        }
        cache?[entry.id] = Stored(entry: entry, isReadOnly: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try CompanionFileFormat.encode(entry).write(to: fileURL(of: entry.id), options: .atomic)
        } catch {
            // The entry stays in memory for this run; the next save tries again.
            companionLog.error("Writing a companion entry failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).\(CompanionFileFormat.fileExtension)", directoryHint: .notDirectory)
    }

    /// The entries whose PDF is not found. After a document-identifier match the bookmarks
    /// were not resolved yet.
    private func notFoundEntries(in entries: [Stored], scanned: [CompanionEntry]?) -> [CompanionEntry] {
        if let scanned { return scanned }
        return entries.map(\.entry).filter { locator.resolve($0.pdf.bookmark) == nil }
    }

    /// The single not-found entry with the same file name and page count that the user has
    /// not declined for this PDF. With several candidates the app does not guess (NOTES-12).
    private func orphan(among notFound: [CompanionEntry], for entry: CompanionEntry) -> CompanionEntry? {
        let candidates = notFound.filter {
            $0.id != entry.id
                && $0.hasStoredData
                && $0.pdf.fileName == entry.pdf.fileName
                && $0.pdf.pageCount == entry.pdf.pageCount
                && !entry.declinedOrphans.contains($0.id)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

extension CompanionEntry {
    /// Whether the entry holds anything worth taking over: settings, notes or drawings.
    public var hasStoredData: Bool { holdsUserContent || !settings.isEmpty }
}
