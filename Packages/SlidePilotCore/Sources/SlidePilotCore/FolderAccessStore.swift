import Foundation

/// The folders the user allowed SlidePilot to read (ADR 0012).
///
/// A sandboxed app reaches only the opened PDF. Videos and `run:` targets next to it
/// (NAV-06, NAV-07) need one grant for their folder, which is kept as a bookmark and then
/// covers every PDF in that folder, also after relaunches.
@MainActor
public final class FolderAccessStore {
    /// The settings key of the stored folder bookmarks.
    public static let key = "folderAccessBookmarks"

    private let settings: any SettingsStore
    private let locator: any PDFLocator
    private let contains: @Sendable (_ folder: URL, _ item: URL) -> Bool

    /// - Parameters:
    ///   - locator: Creates and resolves the bookmarks; works for folders as well as PDFs.
    ///   - contains: Whether `item` lies in `folder` or one of its subfolders. Decided by
    ///     the file system, not by comparing paths (ADR 0012).
    public init(
        settings: any SettingsStore,
        locator: any PDFLocator = FileBookmarkLocator(),
        contains: @escaping @Sendable (_ folder: URL, _ item: URL) -> Bool = FolderAccessStore.fileSystemContains
    ) {
        self.settings = settings
        self.locator = locator
        self.contains = contains
    }

    /// A granted folder that holds `item`, resolved from its bookmark. The caller starts
    /// and stops accessing it as a security-scoped resource. Stale bookmarks are renewed;
    /// bookmarks of folders that are gone are dropped.
    public func grantedFolder(containing item: URL) -> URL? {
        var bookmarks = storedBookmarks
        var found: URL?
        var changed = false
        for (index, bookmark) in bookmarks.enumerated().reversed() {
            guard let resolved = locator.resolve(bookmark) else {
                bookmarks.remove(at: index)
                changed = true
                continue
            }
            if resolved.isStale, let renewed = try? locator.bookmark(for: resolved.url) {
                bookmarks[index] = renewed
                changed = true
            }
            if found == nil, contains(resolved.url, item) {
                found = resolved.url
            }
        }
        if changed { storedBookmarks = bookmarks }
        return found
    }

    /// Keeps a grant for `folder`, which the user just picked. A grant for the same folder
    /// replaces the old one; the newest grant is checked first.
    public func addGrant(for folder: URL) throws {
        let bookmark = try locator.bookmark(for: folder)
        var bookmarks = storedBookmarks.filter { stored in
            guard let resolved = locator.resolve(stored) else { return false }
            return !locator.isSameFile(resolved.url, folder)
        }
        bookmarks.append(bookmark)
        storedBookmarks = bookmarks
    }

    private var storedBookmarks: [Data] {
        get { settings.object(forKey: Self.key) as? [Data] ?? [] }
        set { settings.set(newValue, forKey: Self.key) }
    }

    /// `FileManager`'s relationship check: the folder is the item itself or contains it.
    public static let fileSystemContains: @Sendable (URL, URL) -> Bool = { folder, item in
        var relationship = FileManager.URLRelationship.other
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        guard (try? FileManager.default.getRelationship(&relationship, ofDirectoryAt: folder, toItemAt: item)) != nil
        else { return false }
        return relationship == .contains || relationship == .same
    }
}
