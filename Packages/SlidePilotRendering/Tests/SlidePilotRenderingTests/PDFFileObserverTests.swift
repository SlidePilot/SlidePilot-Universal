import Foundation
import Synchronization
import Testing
@testable import SlidePilotRendering

/// Tests wait for the versions themselves, never against a fixed deadline: on a loaded CI
/// simulator the whole test process ran about 50 times slower than locally (#148), so any
/// deadline is a guess. The time limit only ends a real hang.
@Suite(.timeLimit(.minutes(3)))
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
        #expect(!(await harness.receivesVersions(1, within: .milliseconds(400))))
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
        #expect(!(await harness.receivesVersions(2, within: .milliseconds(300))))
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

    @Test func waitsForACoordinatedWriter() async throws {
        // The read must wait for a writer that still holds the file; otherwise it reads the
        // old bytes and drops the change as unchanged. A slow file system (a loaded CI
        // simulator, an iCloud download) delays a reload but never loses it (#148).
        let file = try TemporaryPDF(pages: 3)
        let harness = Harness(file: file)
        let complete = TestPDF.make(pages: 5)
        let intent = NSFileAccessIntent.writingIntent(with: file.url, options: [])
        try await coordinate(intent) {
            // Blocks only the writer's own queue, like a slow writer would.
            Thread.sleep(forTimeInterval: 0.5)
            try? complete.write(to: intent.url)
        }
        await harness.observer.handle(.contents)
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
        #expect(!(await harness.receivesVersions(1, within: .milliseconds(500))))

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
        #expect(!(await harness.receivesVersions(1, within: .milliseconds(300))))

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
        #expect(!(await harness.receivesVersions(1, within: .milliseconds(300))))

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
        let versions = PDFFileObserver.versions(of: file.url, current: file.initialData, timing: .fast)
        try await waitForPresenterRegistration(at: file.url)
        try TestPDF.make(pages: 5).write(to: file.url, options: atomically ? .atomic : [])
        var iterator = versions.makeAsyncIterator()
        let version = await iterator.next()
        #expect(version?.info.pageCount == 5)
    }
}

/// `NSFileCoordinator.addFilePresenter` returns before the file coordination service knows
/// the presenter, and an uncoordinated write in that gap is never reported. A coordinated
/// read is granted only after the service has processed the registration (it asks the
/// presenter to relinquish the file first), so writes after this call are reported.
///
/// Asynchronous, so the wait does not block a thread of the shared concurrency pool, which
/// all tests of the process run on.
private func waitForPresenterRegistration(at url: URL) async throws {
    try await coordinate(.readingIntent(with: url, options: []))
}

/// Returns once the coordinated access is granted; `accessor` then runs on its own queue and
/// holds the file until it returns. Cancelling the task (the suite's time limit) cancels the
/// coordination, so a hang fails the test instead of blocking the whole run.
private func coordinate(_ intent: NSFileAccessIntent, accessor: @escaping @Sendable () -> Void = {}) async throws {
    let queue = OperationQueue()
    // `NSFileCoordinator` is not Sendable; the mutex hands it to the cancellation handler and
    // keeps it alive until the access was granted or cancelled.
    let coordinator = Mutex(NSFileCoordinator(filePresenter: nil))
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (granted: CheckedContinuation<Void, any Error>) in
            coordinator.withLock { coordinator in
                // Called exactly once, with an error if coordination failed or was cancelled.
                coordinator.coordinate(with: [intent], queue: queue) { error in
                    if let error {
                        granted.resume(throwing: error)
                    } else {
                        granted.resume()
                        accessor()
                    }
                }
            }
        }
    } onCancel: {
        coordinator.withLock { $0.cancel() }
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

    /// Waits until at least `count` versions arrived; false only if the test was cancelled
    /// (by its time limit) first.
    func wait(for count: Int) async -> Bool {
        while !Task.isCancelled {
            if hasArrived(count) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return hasArrived(count)
    }

    /// Whether at least `count` versions arrive within `limit`. Only for checks that nothing
    /// arrives: a slow runner can make them pass wrongly, never fail wrongly.
    func arrive(_ count: Int, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if hasArrived(count) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return hasArrived(count)
    }

    private func hasArrived(_ count: Int) -> Bool {
        versions.withLock { $0.count } >= count
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

    /// Waits for `count` versions without a deadline; see the suite's time limit.
    func waitForVersions(_ count: Int) async -> Bool {
        await received.wait(for: count)
    }

    /// Whether `count` versions arrive within `limit`, for checks that nothing arrives.
    func receivesVersions(_ count: Int, within limit: Duration) async -> Bool {
        await received.arrive(count, within: limit)
    }

    func stop() async {
        await observer.stop()
        consumer.cancel()
    }
}
