import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SlidePilotCore

@Suite struct LinkedFileTests {
    let pdf = URL(filePath: "/talks/2026/media.pdf")

    @Test func resolvesPathRelativeToThePDF() {
        #expect(LinkedFile.resolve("media/test-pattern.mp4", relativeTo: pdf) == URL(filePath: "/talks/2026/media/test-pattern.mp4"))
        #expect(LinkedFile.resolve("plain-slides.pdf", relativeTo: pdf) == URL(filePath: "/talks/2026/plain-slides.pdf"))
    }

    @Test func resolvesParentFolderAndDotSegments() {
        #expect(LinkedFile.resolve("../videos/a.mov", relativeTo: pdf) == URL(filePath: "/talks/videos/a.mov"))
        #expect(LinkedFile.resolve("./a.mov", relativeTo: pdf) == URL(filePath: "/talks/2026/a.mov"))
    }

    /// The old app used `URL(string:relativeTo:)`, which fails on spaces.
    @Test func resolvesPathsWithSpaces() {
        #expect(LinkedFile.resolve("my video.mp4", relativeTo: pdf) == URL(filePath: "/talks/2026/my video.mp4"))
    }

    @Test func keepsAbsolutePathsAndFileURLs() {
        #expect(LinkedFile.resolve("/Movies/a.mp4", relativeTo: pdf) == URL(filePath: "/Movies/a.mp4"))
        #expect(LinkedFile.resolve("file:///Movies/a.mp4", relativeTo: pdf) == URL(filePath: "/Movies/a.mp4"))
    }

    @Test func keepsWebAddresses() {
        #expect(LinkedFile.resolve("https://example.com/a.mp4", relativeTo: pdf) == URL(string: "https://example.com/a.mp4"))
        #expect(LinkedFile.resolve("http://example.com/a.mp4", relativeTo: pdf) == URL(string: "http://example.com/a.mp4"))
    }

    @Test func refusesOtherSchemesAndEmptyReferences() {
        #expect(LinkedFile.resolve("javascript:alert(1)", relativeTo: pdf) == nil)
        #expect(LinkedFile.resolve("ftp://example.com/a.mp4", relativeTo: pdf) == nil)
        #expect(LinkedFile.resolve("  ", relativeTo: pdf) == nil)
    }
}

@Suite struct RunLinkPolicyTests {
    @Test(arguments: ["pdf", "mp4", "mov", "key", "pptx", "docx", "txt", "png", "html"])
    func opensDocumentsAndMedia(_ fileExtension: String) {
        #expect(RunLinkPolicy.allowsOpening(UTType(filenameExtension: fileExtension), fileExtension: fileExtension))
    }

    @Test(arguments: ["app", "command", "sh", "scpt", "pkg", "workflow", "exe", "py", "fileloc", "webloc"])
    func refusesProgramsAndScripts(_ fileExtension: String) {
        #expect(!RunLinkPolicy.allowsOpening(UTType(filenameExtension: fileExtension), fileExtension: fileExtension))
    }

    @Test func refusesExecutablesAndUnknownTypes() {
        #expect(!RunLinkPolicy.allowsOpening(.unixExecutable))
        #expect(!RunLinkPolicy.allowsOpening(nil))
        // A runnable format without a registered type is refused by its extension.
        #expect(!RunLinkPolicy.allowsOpening(.data, fileExtension: "Workflow"))
    }
}

@MainActor
@Suite struct FolderAccessStoreTests {
    let locator = FakeLocator()
    let settings = InMemorySettingsStore()

    /// Paths stand in for the file system's relationship check.
    func store() -> FolderAccessStore {
        FolderAccessStore(settings: settings, locator: locator) { folder, item in
            item.path.hasPrefix(folder.path + "/") || item == folder
        }
    }

    func addFolder(_ path: String, id: String) -> URL {
        let url = URL(filePath: path)
        locator.files[id] = FakeLocator.File(url: url)
        return url
    }

    @Test func hasNoGrantAtFirst() {
        #expect(store().grantedFolder(containing: URL(filePath: "/talks/media.pdf")) == nil)
    }

    @Test func grantCoversFilesInTheFolderAndBelow() throws {
        let folder = addFolder("/talks", id: "talks")
        try store().addGrant(for: folder)
        // A new store reads the grant back, like after a relaunch.
        let store = store()
        #expect(store.grantedFolder(containing: URL(filePath: "/talks/media.pdf")) == folder)
        #expect(store.grantedFolder(containing: URL(filePath: "/talks/media/a.mp4")) == folder)
        #expect(store.grantedFolder(containing: URL(filePath: "/other/a.mp4")) == nil)
    }

    @Test func followsAMovedFolder() throws {
        let folder = addFolder("/talks", id: "talks")
        try store().addGrant(for: folder)
        locator.files["talks"] = FakeLocator.File(url: URL(filePath: "/archive/talks"), isStale: true)
        let store = store()
        #expect(store.grantedFolder(containing: URL(filePath: "/archive/talks/media.pdf")) == URL(filePath: "/archive/talks"))
        // The stale bookmark was renewed.
        #expect(locator.files["talks"]?.isStale == false)
    }

    @Test func dropsGrantsOfFoldersThatAreGone() throws {
        let folder = addFolder("/talks", id: "talks")
        try store().addGrant(for: folder)
        locator.files["talks"] = nil
        #expect(store().grantedFolder(containing: URL(filePath: "/talks/media.pdf")) == nil)
        #expect((settings.object(forKey: FolderAccessStore.key) as? [Data])?.isEmpty == true)
    }

    @Test func grantingTheSameFolderAgainKeepsOneBookmark() throws {
        let folder = addFolder("/talks", id: "talks")
        try store().addGrant(for: folder)
        try store().addGrant(for: folder)
        #expect((settings.object(forKey: FolderAccessStore.key) as? [Data])?.count == 1)
    }

    @Test func keepsGrantsForSeveralFolders() throws {
        let talks = addFolder("/talks", id: "talks")
        let lectures = addFolder("/lectures", id: "lectures")
        try store().addGrant(for: talks)
        try store().addGrant(for: lectures)
        #expect(store().grantedFolder(containing: URL(filePath: "/talks/a.pdf")) == talks)
        #expect(store().grantedFolder(containing: URL(filePath: "/lectures/b.pdf")) == lectures)
    }
}
