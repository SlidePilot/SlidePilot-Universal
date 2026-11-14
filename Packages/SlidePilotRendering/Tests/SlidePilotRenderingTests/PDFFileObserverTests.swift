import Foundation
import Synchronization
import Testing
@testable import SlidePilotRendering

@Suite
struct PDFFileObserverTests {
    // MARK: - Validation

    @Test func acceptsCompletePDF() {
        let info = PDFFileObserver.validate(TestPDF.make(pages: 3))
        #expect(info?.pageCount == 3)
    }

    @Test func rejectsFileWithoutEndMarker() {
        // PDFKit still opens a Core Graphics PDF without its last bytes (#10).
        let data = TestPDF.make(pages: 3)
        #expect(PDFFileObserver.validate(data.prefix(data.count - 8)) == nil)
    }

    @Test func rejectsHalfWrittenFile() {
        let data = TestPDF.make(pages: 3)
        #expect(PDFFileObserver.validate(data.prefix(data.count / 2)) == nil)
        #expect(PDFFileObserver.validate(Data()) == nil)
    }

    @Test func rejectsOtherFormats() {
        #expect(PDFFileObserver.validate(Data("not a pdf %%EOF".utf8)) == nil)
    }

    @Test func rejectsLockedPDF() {
        #expect(PDFFileObserver.validate(TestPDF.make(pages: 2, userPassword: "secret")) == nil)
    }

    // MARK: - Pipeline

    @Test func reloadsChangedFile() async throws {
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        try file.write(pages: 5)
        await harness.observer.handle(.contents)
        #expect(await harness.waitForVersions(1))
        #expect(harness.pageCounts == [5])
        await harness.stop()
    }

    @Test func ignoresUnchangedBytes() async throws {
        // Spotlight, Quick Look and iCloud report changes without new bytes.
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        // Same bytes in a new file, like an atomic save of an unchanged deck.
        try file.initialData.write(to: file.url, options: .atomic)
        await harness.observer.handle(.contents)
        #expect(!(await harness.waitForVersions(1, within: .milliseconds(400))))
        await harness.stop()
    }

    @Test func burstOfChangesReloadsOnce() async throws {
        let file = try TemporaryPDF(pages: 3)
        // A quiet period well above the time between the writes, so the debounce restarts.
        let harness = Harness(file: file, timing: .init(quietPeriod: .milliseconds(300), retryDelay: .milliseconds(30), maxAttempts: 8))
        let versions = [4, 5, 6].map { TestPDF.make(pages: $0) }
        for data in versions {
            try data.write(to: file.url)
            await harness.observer.handle(.contents)
        }
        #expect(await harness.waitForVersions(1))
        #expect(!(await harness.waitForVersions(2, within: .milliseconds(300))))
        #expect(harness.pageCounts == [6])
        await harness.stop()
    }

    @Test func waitsUntilFileIsComplete() async throws {
        let file = try TemporaryPDF(pages: 3)
        // Retries for 1.5 s, so a slow test runner still finishes the write in time.
        let harness = Harness(file: file, timing: .init(quietPeriod: .milliseconds(30), retryDelay: .milliseconds(30), maxAttempts: 50))
        let complete = TestPDF.make(pages: 5)
        try complete.prefix(complete.count / 2).write(to: file.url)
        await harness.observer.handle(.contents)
        // The writer finishes while the pipeline retries; no new change is reported.
        try await Task.sleep(for: .milliseconds(100))
        try complete.write(to: file.url)
        #expect(await harness.waitForVersions(1))
        #expect(harness.pageCounts == [5])
        await harness.stop()
    }

    @Test func keepsLoadedVersionWhenFileStaysIncomplete() async throws {
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        let complete = TestPDF.make(pages: 5)
        try complete.prefix(complete.count - 8).write(to: file.url)
        await harness.observer.handle(.contents)
        #expect(!(await harness.waitForVersions(1, within: .milliseconds(500))))

        // The next change starts over.
        try complete.write(to: file.url)
        await harness.observer.handle(.contents)
        #expect(await harness.waitForVersions(1))
        #expect(harness.pageCounts == [5])
        await harness.stop()
    }

    @Test func followsMovedFile() async throws {
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        let moved = file.folder.appending(path: "moved.pdf")
        try FileManager.default.moveItem(at: file.url, to: moved)
        await harness.observer.handle(.moved(moved))
        // A rename alone does not reload.
        #expect(!(await harness.waitForVersions(1, within: .milliseconds(300))))

        try TestPDF.make(pages: 2).write(to: moved)
        await harness.observer.handle(.contents)
        #expect(await harness.waitForVersions(1))
        #expect(harness.pageCounts == [2])
        await harness.stop()
    }

    @Test func missingFileKeepsLoadedVersion() async throws {
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        try FileManager.default.removeItem(at: file.url)
        await harness.observer.handle(.contents)
        #expect(!(await harness.waitForVersions(1, within: .milliseconds(300))))

        // Delete and recreate, like a build script that cleans first.
        try file.write(pages: 4)
        await harness.observer.handle(.contents)
        #expect(await harness.waitForVersions(1))
        #expect(harness.pageCounts == [4])
        await harness.stop()
    }

    // MARK: - File presenter

    // The presenter reports uncoordinated writes about 1 s after the write (#10).
    @Test(arguments: [false, true])
    func presenterReportsRewrite(atomically: Bool) async throws {
        let file = try TemporaryPDF(pages: 3)
        let received = Received()
        let versions = PDFFileObserver.versions(of: file.url, current: file.initialData, timing: .fast)
        let consumer = Task {
            for await version in versions {
                received.append(version)
            }
        }
        defer { consumer.cancel() }
        // The presenter registers asynchronously, so a single early write may go unseen.
        // Rewrite until a version arrives.
        let rewrite = TestPDF.make(pages: 5)
        var arrived = false
        for _ in 0..<10 where !arrived {
            try rewrite.write(to: file.url, options: atomically ? .atomic : [])
            arrived = await received.wait(for: 1, within: .seconds(2))
        }
        #expect(arrived)
        #expect(received.pageCounts.allSatisfy { $0 == 5 })
    }
}

// MARK: - Helpers

extension PDFFileObserver.Timing {
    static let fast = Self(quietPeriod: .milliseconds(30), retryDelay: .milliseconds(30), maxAttempts: 8)
}

/// A PDF in its own temporary folder, removed when the test ends.
private final class TemporaryPDF {
    let folder: URL
    let url: URL
    let initialData: Data

    init(pages: Int) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PDFFileObserverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "slides.pdf")
        initialData = TestPDF.make(pages: pages)
        try initialData.write(to: url)
    }

    /// Rewrites the file in place, like pdflatex.
    func write(pages: Int) throws {
        try TestPDF.make(pages: pages).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Collects the versions a stream yields.
private final class Received: Sendable {
    private let versions = Mutex<[PDFVersion]>([])

    func append(_ version: PDFVersion) {
        versions.withLock { $0.append(version) }
    }

    var pageCounts: [Int] { versions.withLock { $0.map(\.info.pageCount) } }

    /// Whether at least `count` versions arrived within `limit`.
    func wait(for count: Int, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if versions.withLock({ $0.count }) >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return versions.withLock { $0.count } >= count
    }
}

/// An observer fed with changes by the test instead of a file presenter.
private struct Harness {
    let observer: PDFFileObserver
    private let received = Received()
    private let consumer: Task<Void, Never>

    init(file: TemporaryPDF, timing: PDFFileObserver.Timing = .fast) {
        let (versions, output) = AsyncStream.makeStream(of: PDFVersion.self)
        observer = PDFFileObserver(url: file.url, current: file.initialData, timing: timing, output: output)
        consumer = Task { [received] in
            for await version in versions {
                received.append(version)
            }
        }
    }

    var pageCounts: [Int] { received.pageCounts }

    func waitForVersions(_ count: Int, within limit: Duration = .seconds(3)) async -> Bool {
        await received.wait(for: count, within: limit)
    }

    func stop() async {
        await observer.stop()
        consumer.cancel()
    }
}
