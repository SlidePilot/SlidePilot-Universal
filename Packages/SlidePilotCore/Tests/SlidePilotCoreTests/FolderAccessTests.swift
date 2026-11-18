import Foundation
import Testing
@testable import SlidePilotCore

/// Bookmarks are the folder paths; "contains" compares path components.
private final class FakeFolderBookmarks: FolderBookmarking, @unchecked Sendable {
    // Only touched from the main-actor tests below.
    var existing: Set<String>
    var stale: Set<String> = []

    init(existing: Set<String>) {
        self.existing = existing
    }

    func bookmark(forFolder url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        let path = String(decoding: bookmark, as: UTF8.self)
        guard existing.contains(path) else { return nil }
        return ResolvedBookmark(url: URL(filePath: path), isStale: stale.contains(path))
    }

    func folder(_ folder: URL, contains item: URL) -> Bool {
        item.pathComponents.starts(with: folder.pathComponents)
    }
}

@MainActor
@Suite struct FolderAccessTests {
    @Test func noGrantCoversNothing() {
        let access = FolderAccess(store: InMemorySettingsStore(), bookmarks: FakeFolderBookmarks(existing: []))
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) == nil)
    }

    // ADR 0012: one grant covers every PDF in the folder and its subfolders.
    @Test func grantCoversFilesInTheFolderAndSubfolders() {
        let access = FolderAccess(store: InMemorySettingsStore(), bookmarks: FakeFolderBookmarks(existing: ["/Talks"]))
        #expect(access.addGrant(for: URL(filePath: "/Talks")))
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a-Notes.rtf"))?.path == "/Talks")
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/2026/b.pdf"))?.path == "/Talks")
        #expect(access.grantedFolder(containing: URL(filePath: "/Other/a.pdf")) == nil)
    }

    @Test func grantsSurviveARelaunch() {
        let store = InMemorySettingsStore()
        let bookmarks = FakeFolderBookmarks(existing: ["/Talks"])
        FolderAccess(store: store, bookmarks: bookmarks).addGrant(for: URL(filePath: "/Talks"))
        let relaunched = FolderAccess(store: store, bookmarks: bookmarks)
        #expect(relaunched.grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
    }

    @Test func grantingTheSameFolderTwiceKeepsOneGrant() {
        let store = InMemorySettingsStore()
        let access = FolderAccess(store: store, bookmarks: FakeFolderBookmarks(existing: ["/Talks", "/Other"]))
        access.addGrant(for: URL(filePath: "/Talks"))
        access.addGrant(for: URL(filePath: "/Other"))
        access.addGrant(for: URL(filePath: "/Talks"))
        #expect((store.values[FolderAccess.defaultsKey] as? [Data])?.count == 2)
    }

    @Test func removesGrantsOfFoldersThatAreGone() {
        let store = InMemorySettingsStore()
        let bookmarks = FakeFolderBookmarks(existing: ["/Talks", "/Gone"])
        let access = FolderAccess(store: store, bookmarks: bookmarks)
        access.addGrant(for: URL(filePath: "/Gone"))
        access.addGrant(for: URL(filePath: "/Talks"))
        bookmarks.existing = ["/Talks"]
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
        #expect((store.values[FolderAccess.defaultsKey] as? [Data]) == [Data("/Talks".utf8)])
    }

    @Test func refreshesStaleBookmarks() {
        let store = InMemorySettingsStore(values: [FolderAccess.defaultsKey: [Data("/Talks".utf8)]])
        let bookmarks = FakeFolderBookmarks(existing: ["/Talks"])
        bookmarks.stale = ["/Talks"]
        let access = FolderAccess(store: store, bookmarks: bookmarks)
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
        #expect((store.values[FolderAccess.defaultsKey] as? [Data]) == [Data("/Talks".utf8)])
    }
}

/// The real relationship check on temporary folders.
@Suite struct FileFolderBookmarksTests {
    @Test func folderContainsItsFilesAndSubfoldersOnly() throws {
        let root = URL.temporaryDirectory.appending(path: "FolderAccessTests-\(UUID().uuidString)")
        let sub = root.appending(path: "sub")
        let other = URL.temporaryDirectory.appending(path: "FolderAccessTests-other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        let file = sub.appending(path: "talk-Notes.rtf")
        try Data("x".utf8).write(to: file)

        let bookmarks = FileFolderBookmarks()
        #expect(bookmarks.folder(root, contains: file))
        #expect(bookmarks.folder(root, contains: sub))
        #expect(bookmarks.folder(root, contains: root))
        #expect(!bookmarks.folder(sub, contains: root))
        #expect(!bookmarks.folder(other, contains: file))
    }

    @Test func bookmarkResolvesToTheSameFolder() throws {
        let root = URL.temporaryDirectory.appending(path: "FolderAccessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bookmarks = FileFolderBookmarks()
        let resolved = try #require(bookmarks.resolve(bookmarks.bookmark(forFolder: root)))
        #expect(bookmarks.folder(resolved.url, contains: root) && bookmarks.folder(root, contains: resolved.url))
    }
}
