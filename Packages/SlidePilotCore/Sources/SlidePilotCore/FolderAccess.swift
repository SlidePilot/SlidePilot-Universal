import Foundation

/// Creates and resolves folder bookmarks for `FolderAccess`. Injected so tests run
/// without real bookmarks and security scopes.
public protocol FolderBookmarking: Sendable {
    func bookmark(forFolder url: URL) throws -> Data
    /// `nil` when the folder is gone or not reachable.
    func resolve(_ bookmark: Data) -> ResolvedBookmark?
    /// Whether `item` is inside `folder` or one of its subfolders. Decided by file system
    /// relationship, not by path strings, which differ for the same folder (ADR 0012).
    func folder(_ folder: URL, contains item: URL) -> Bool
}

/// Folders the user allowed the app to read, kept as bookmarks across launches (ADR 0012).
///
/// The sandbox only lets the app read the opened PDF. Files next to it, such as legacy
/// notes (NOTES-08), need a folder grant, which the user gives once per folder in an open
/// panel; one grant covers every PDF in that folder and its subfolders.
@MainActor
public final class FolderAccess {
    public static let defaultsKey = "folderAccessBookmarks"

    private let store: SettingsStore
    private let bookmarks: FolderBookmarking

    public init(store: SettingsStore, bookmarks: FolderBookmarking = FileFolderBookmarks()) {
        self.store = store
        self.bookmarks = bookmarks
    }

    private var stored: [Data] {
        get { store.object(forKey: Self.defaultsKey) as? [Data] ?? [] }
        set { store.set(newValue, forKey: Self.defaultsKey) }
    }

    /// The granted folder that contains `item`, ready for
    /// `startAccessingSecurityScopedResource()`; `nil` if no grant covers it. Grants whose
    /// folder is gone are removed; stale bookmarks are created again.
    public func grantedFolder(containing item: URL) -> URL? {
        var updated = stored
        var match: URL?
        for (index, data) in stored.enumerated().reversed() {
            guard let resolved = bookmarks.resolve(data) else {
                updated.remove(at: index)
                continue
            }
            if resolved.isStale, let fresh = try? bookmarks.bookmark(forFolder: resolved.url) {
                updated[index] = fresh
            }
            if match == nil, bookmarks.folder(resolved.url, contains: item) {
                match = resolved.url
            }
        }
        if updated != stored {
            stored = updated
        }
        return match
    }

    /// Stores the grant for a folder the user picked. Returns `false` if no bookmark could
    /// be created; the access then lasts only until the app quits.
    @discardableResult
    public func addGrant(for folder: URL) -> Bool {
        guard let data = try? bookmarks.bookmark(forFolder: folder) else { return false }
        // The newest grant comes last; a grant for the same folder replaces the old one.
        let others = stored.filter { existing in
            guard let resolved = bookmarks.resolve(existing) else { return false }
            return !(bookmarks.folder(resolved.url, contains: folder) && bookmarks.folder(folder, contains: resolved.url))
        }
        stored = others + [data]
        return true
    }
}

/// `FolderBookmarking` with Foundation bookmarks: security-scoped and read-only on macOS
/// (the app reads neighbouring files but never writes them), plain on iPadOS, where every
/// bookmark carries its scope.
public struct FileFolderBookmarks: FolderBookmarking {
    public init() {}

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI, .withoutMounting]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
    #endif

    public func bookmark(forFolder url: URL) throws -> Data {
        try withAccess(to: url) {
            try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    public func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else { return nil }
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    public func folder(_ folder: URL, contains item: URL) -> Bool {
        withAccess(to: folder) {
            var relationship = FileManager.URLRelationship.other
            do {
                try FileManager.default.getRelationship(&relationship, ofDirectoryAt: folder, toItemAt: item)
            } catch {
                return false
            }
            return relationship == .contains || relationship == .same
        }
    }

    private func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }
}
