import Foundation
import SlidePilotCore
import Testing

@Suite struct EmbeddedFileStoreTests {
    private func makeParent() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "EmbeddedFileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func writesTheDataOnceWithItsExtension() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let data = Data("video".utf8)
        let first = try await store.file(for: data, fileExtension: "MP4")
        #expect(first.pathExtension == "mp4")
        #expect(first.deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL)
        #expect(try Data(contentsOf: first) == data)
        // The same video, also from another annotation or a reloaded PDF, gets the same file.
        let second = try await store.file(for: data, fileExtension: "mp4")
        #expect(second == first)
        #expect(await store.files == [first])
    }

    @Test func differentContentGetsAnotherFile() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let first = try await store.file(for: Data("one".utf8), fileExtension: "mov")
        let second = try await store.file(for: Data("two".utf8), fileExtension: "mov")
        #expect(first != second)
    }

    @Test func keepsOnlySafeExtensionCharacters() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let url = try await store.file(for: Data("x".utf8), fileExtension: "../m p4")
        #expect(url.lastPathComponent.hasSuffix(".mp4"))
        #expect(url.deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL)
        let bare = try await store.file(for: Data("y".utf8), fileExtension: "")
        #expect(bare.pathExtension.isEmpty)
    }

    @Test func writesAgainWhenTheFileWasRemoved() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let data = Data("video".utf8)
        let url = try await store.file(for: data, fileExtension: "mp4")
        try FileManager.default.removeItem(at: url)
        #expect(try await store.file(for: data, fileExtension: "mp4") == url)
        #expect(exists(url))
    }

    @Test func removesFilesThatAReloadNoLongerUses() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let kept = try await store.file(for: Data("kept".utf8), fileExtension: "mp4")
        let dropped = try await store.file(for: Data("dropped".utf8), fileExtension: "mp4")
        await store.removeAll(except: [kept])
        #expect(exists(kept))
        #expect(!exists(dropped))
        #expect(await store.files == [kept])
    }

    /// An older reload must not remove a file that a newer reload asked for meanwhile.
    @Test func keepsFilesRequestedAfterTheMark() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let old = try await store.file(for: Data("old".utf8), fileExtension: "mp4")
        let stale = try await store.file(for: Data("stale".utf8), fileExtension: "mp4")
        let mark = await store.mark()
        // The newer reload uses `old` again while the older one decides.
        _ = try await store.file(for: Data("old".utf8), fileExtension: "mp4")
        await store.removeAll(except: [], requestedSince: mark)
        #expect(exists(old))
        #expect(!exists(stale))
    }

    /// Closing the document empties the store at once, even while the session lives on.
    @Test func removesEverythingWhenTheDocumentCloses() async throws {
        let parent = makeParent()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let store = EmbeddedFileStore(parent: parent)
        let url = try await store.file(for: Data("video".utf8), fileExtension: "mp4")
        await store.removeAll()
        #expect(!exists(store.directory))
        #expect(await store.files.isEmpty)
        // A late request writes the file again.
        #expect(try await store.file(for: Data("video".utf8), fileExtension: "mp4") == url)
        #expect(exists(url))
    }

    @Test func removesLeftoversOfEarlierLaunches() async throws {
        let parent = makeParent()
        let store = EmbeddedFileStore(parent: parent)
        let url = try await store.file(for: Data("video".utf8), fileExtension: "mp4")
        EmbeddedFileStore.removeLeftovers(in: parent)
        #expect(!exists(url))
        #expect(!exists(parent))
    }
}
