import Foundation
import Synchronization
import Testing
@testable import SlidePilotCore

/// Bookmarks are folder paths; only folders in `existing` resolve.
private final class PathLocator: PDFLocator {
    private let state = Mutex((existing: Set<String>(), stale: Set<String>()))

    init(existing: Set<String>) {
        state.withLock { $0.existing = existing }
    }

    var existing: Set<String> {
        get { state.withLock { $0.existing } }
        set { state.withLock { $0.existing = newValue } }
    }

    var stale: Set<String> {
        get { state.withLock { $0.stale } }
        set { state.withLock { $0.stale = newValue } }
    }

    func bookmark(for url: URL) throws -> Data { Data(url.path.utf8) }

    func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        let path = String(decoding: bookmark, as: UTF8.self)
        guard existing.contains(path) else { return nil }
        return ResolvedBookmark(url: URL(filePath: path), isStale: stale.contains(path))
    }

    func isSameFile(_ first: URL, _ second: URL) -> Bool { first == second }
    func documentIdentifier(of url: URL) -> Int? { nil }
}

private func pathContains(_ folder: URL, _ item: URL) -> Bool {
    item.pathComponents.starts(with: folder.pathComponents)
}

@MainActor
@Suite struct FolderAccessStoreTests {
    private func store(_ locator: PathLocator, _ settings: InMemorySettingsStore = InMemorySettingsStore()) -> FolderAccessStore {
        FolderAccessStore(settings: settings, locator: locator, contains: pathContains)
    }

    private func stored(_ settings: InMemorySettingsStore) -> [Data]? {
        settings.values[FolderAccessStore.settingsKey] as? [Data]
    }

    @Test func noGrantCoversNothing() {
        #expect(store(PathLocator(existing: [])).grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) == nil)
    }

    // ADR 0012: one grant covers every file in the folder and its subfolders.
    @Test func grantCoversFilesInTheFolderAndSubfolders() throws {
        let access = store(PathLocator(existing: ["/Talks"]))
        try access.addGrant(for: URL(filePath: "/Talks"))
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a-Notes.rtf"))?.path == "/Talks")
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/2026/b.pdf"))?.path == "/Talks")
        #expect(access.grantedFolder(containing: URL(filePath: "/Other/a.pdf")) == nil)
    }

    @Test func grantsSurviveARelaunch() throws {
        let settings = InMemorySettingsStore()
        let locator = PathLocator(existing: ["/Talks"])
        try store(locator, settings).addGrant(for: URL(filePath: "/Talks"))
        #expect(store(locator, settings).grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
    }

    @Test func grantingTheSameFolderTwiceKeepsOneGrant() throws {
        let settings = InMemorySettingsStore()
        let access = store(PathLocator(existing: ["/Talks", "/Other"]), settings)
        try access.addGrant(for: URL(filePath: "/Talks"))
        try access.addGrant(for: URL(filePath: "/Other"))
        try access.addGrant(for: URL(filePath: "/Talks"))
        #expect(stored(settings)?.count == 2)
    }

    @Test func removesGrantsOfFoldersThatAreGone() throws {
        let settings = InMemorySettingsStore()
        let locator = PathLocator(existing: ["/Talks", "/Gone"])
        let access = store(locator, settings)
        try access.addGrant(for: URL(filePath: "/Gone"))
        try access.addGrant(for: URL(filePath: "/Talks"))
        locator.existing = ["/Talks"]
        #expect(access.grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
        #expect(stored(settings) == [Data("/Talks".utf8)])
    }

    @Test func staleBookmarksStillCover() {
        let settings = InMemorySettingsStore(values: [FolderAccessStore.settingsKey: [Data("/Talks".utf8)]])
        let locator = PathLocator(existing: ["/Talks"])
        locator.stale = ["/Talks"]
        #expect(store(locator, settings).grantedFolder(containing: URL(filePath: "/Talks/a.pdf")) != nil)
        #expect(stored(settings) == [Data("/Talks".utf8)])
    }
}

/// The real relationship check on temporary folders.
@Suite struct FolderContainsTests {
    @Test func folderContainsItsFilesAndSubfoldersOnly() throws {
        let root = URL.temporaryDirectory.appending(path: "FolderAccessStoreTests-\(UUID().uuidString)")
        let sub = root.appending(path: "sub")
        let other = URL.temporaryDirectory.appending(path: "FolderAccessStoreTests-other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        let file = sub.appending(path: "talk-Notes.rtf")
        try Data("x".utf8).write(to: file)

        #expect(FolderAccessStore.folderContains(root, file))
        #expect(FolderAccessStore.folderContains(root, sub))
        #expect(FolderAccessStore.folderContains(root, root))
        #expect(!FolderAccessStore.folderContains(sub, root))
        #expect(!FolderAccessStore.folderContains(other, file))
    }
}
