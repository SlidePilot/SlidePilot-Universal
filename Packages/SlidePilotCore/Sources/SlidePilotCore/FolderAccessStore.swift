import Foundation

/// Folders the user allowed the app to read, kept as bookmarks across launches (ADR 0012).
///
/// The sandbox only lets the app read the opened PDF. Files next to it, such as legacy
/// notes (NOTES-08), need a folder grant, which the user gives once per folder in an open
/// panel; one grant covers every file in that folder and its subfolders.
@MainActor
public final class FolderAccessStore {
    public static let settingsKey = "folderAccessBookmarks"

    private let settings: any SettingsStore
    private let locator: any PDFLocator
    private let contains: (_ folder: URL, _ item: URL) -> Bool

    /// - Parameter contains: Whether `item` is inside `folder` or one of its subfolders.
    ///   Decided by file system relationship, never by path strings (ADR 0012).
    public init(
        settings: any SettingsStore,
        locator: any PDFLocator = FileBookmarkLocator(),
        contains: @escaping (_ folder: URL, _ item: URL) -> Bool = FolderAccessStore.folderContains
    ) {
        self.settings = settings
        self.locator = locator
        self.contains = contains
    }

    private var stored: [Data] {
        get { settings.object(forKey: Self.settingsKey) as? [Data] ?? [] }
        set { settings.set(newValue, forKey: Self.settingsKey) }
    }

    /// The granted folder that contains `item`; `nil` if no grant covers it. The caller
    /// starts and stops security-scoped access on the returned URL. Grants whose folder is
    /// gone are removed; stale bookmarks are created again.
    public func grantedFolder(containing item: URL) -> URL? {
        var updated = stored
        var match: URL?
        for (index, data) in stored.enumerated().reversed() {
            guard let resolved = locator.resolve(data) else {
                updated.remove(at: index)
                continue
            }
            if resolved.isStale, let fresh = try? locator.bookmark(for: resolved.url) {
                updated[index] = fresh
            }
            if match == nil, contains(resolved.url, item) {
                match = resolved.url
            }
        }
        if updated != stored {
            stored = updated
        }
        return match
    }

    /// Stores the grant for a folder the user picked; a grant for the same folder is
    /// replaced. Throws if no bookmark can be created; access then lasts until the app quits.
    public func addGrant(for folder: URL) throws {
        let data = try locator.bookmark(for: folder)
        let others = stored.filter { existing in
            guard let resolved = locator.resolve(existing) else { return false }
            return !(contains(resolved.url, folder) && contains(folder, resolved.url))
        }
        stored = others + [data]
    }

    /// The default relationship check: `item` is `folder` itself or inside it.
    public nonisolated static func folderContains(_ folder: URL, _ item: URL) -> Bool {
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { folder.stopAccessingSecurityScopedResource() }
        }
        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(&relationship, ofDirectoryAt: folder, toItemAt: item)
        } catch {
            return false
        }
        return relationship == .contains || relationship == .same
    }
}
