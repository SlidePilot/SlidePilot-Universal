import Foundation
import Synchronization

/// Reports changes of the opened PDF on disk (ADR 0013).
///
/// A file presenter sees every way a PDF gets rewritten: in-place writes by pdflatex,
/// atomic saves, delete and recreate, coordinated writes and iCloud sync. It reports about
/// one second after an uncoordinated write and runs on its own `OperationQueue`.
final class PDFFilePresenter: NSObject, NSFilePresenter, Sendable {
    enum Change: Sendable, Equatable {
        /// The contents may have changed. Spurious reports are common (Spotlight, Quick Look),
        /// so the receiver compares the bytes.
        case contents
        /// The file was renamed or moved; it is presented at the new URL from now on.
        case moved(URL)
    }

    let changes: AsyncStream<Change>
    let presentedItemOperationQueue: OperationQueue
    private let continuation: AsyncStream<Change>.Continuation
    private let url: Mutex<URL>

    init(url: URL) {
        (changes, continuation) = AsyncStream.makeStream(of: Change.self)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        self.url = Mutex(url)
    }

    var presentedItemURL: URL? { url.withLock { $0 } }

    /// Starts reporting changes.
    func start() {
        NSFileCoordinator.addFilePresenter(self)
    }

    /// Stops reporting changes and ends `changes`.
    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
        continuation.finish()
    }

    func presentedItemDidChange() {
        continuation.yield(.contents)
    }

    func presentedItemDidMove(to newURL: URL) {
        url.withLock { $0 = newURL }
        continuation.yield(.moved(newURL))
    }

    /// Keeps showing the loaded version; a recompile that deletes and recreates the file
    /// reports the new file as a change.
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        completionHandler(nil)
    }

    /// iCloud metadata changes often (download progress, sync state) and never changes the
    /// PDF itself; content changes still arrive through `presentedItemDidChange()`.
    func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) {}
}
