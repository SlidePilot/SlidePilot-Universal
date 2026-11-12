import Foundation

// PROTOTYPE (issue #9). Never merged into main.

/// Stores security-scoped bookmarks for PDFs and granted folders in UserDefaults.
nonisolated enum GrantStore {
    #if os(macOS)
    static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let creationOptions: URL.BookmarkCreationOptions = []
    static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    private static let folderKey = "prototypeFolderBookmarks"
    private static let fileKey = "prototypeFileBookmarks"
    private static let maxFiles = 10

    struct Resolved: Sendable {
        let url: URL
        let isStale: Bool
    }

    static func storeFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        var list = UserDefaults.standard.array(forKey: folderKey) as? [Data] ?? []
        list.append(data)
        UserDefaults.standard.set(list, forKey: folderKey)
    }

    static func storeFile(_ url: URL) throws {
        let data = try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        var list = UserDefaults.standard.array(forKey: fileKey) as? [Data] ?? []
        list.insert(data, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxFiles)), forKey: fileKey)
    }

    static func folders() -> [Result<Resolved, any Error>] {
        resolveAll(key: folderKey)
    }

    static func files() -> [Result<Resolved, any Error>] {
        resolveAll(key: fileKey)
    }

    /// The stored folder grant that contains `url`, if any.
    static func folder(containing url: URL) -> Resolved? {
        let path = url.deletingLastPathComponent().standardizedFileURL.path
        for case .success(let folder) in folders() {
            let folderPath = folder.url.standardizedFileURL.path
            if path == folderPath || path.hasPrefix(folderPath + "/") { return folder }
        }
        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: folderKey)
        UserDefaults.standard.removeObject(forKey: fileKey)
    }

    private static func resolveAll(key: String) -> [Result<Resolved, any Error>] {
        let list = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return list.map { data in
            Result {
                var isStale = false
                let url = try URL(resolvingBookmarkData: data, options: resolutionOptions,
                                  relativeTo: nil, bookmarkDataIsStale: &isStale)
                return Resolved(url: url, isStale: isStale)
            }
        }
    }
}
