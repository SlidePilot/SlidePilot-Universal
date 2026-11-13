import Foundation
import Synchronization

/// A new version of the opened PDF, read completely into memory and validated.
public struct PDFVersion: Sendable {
    public let data: Data
    public let info: PDFDocumentInfo
}

/// Watches the opened PDF and reloads it when a LaTeX recompile changes it (DOC-08, ADR 0013).
///
/// Every change goes through one pipeline: wait until the file has been quiet for a moment,
/// read the whole file with coordination inside the security scope, check that it is a
/// complete PDF, retry while it is still being written, and drop versions whose bytes did
/// not change.
public actor PDFFileObserver {
    public struct Timing: Sendable {
        /// How long the file must be quiet after a change before it is read.
        public var quietPeriod: Duration
        /// Delay between reads of a file that is not yet a complete PDF.
        public var retryDelay: Duration
        public var maxAttempts: Int

        public init(quietPeriod: Duration, retryDelay: Duration, maxAttempts: Int) {
            self.quietPeriod = quietPeriod
            self.retryDelay = retryDelay
            self.maxAttempts = maxAttempts
        }

        /// Measured in #10 (`docs/prototypes/auto-reload.md`).
        public static let standard = Timing(quietPeriod: .milliseconds(300), retryDelay: .milliseconds(300), maxAttempts: 10)
    }

    private var url: URL
    private var current: Data
    private let timing: Timing
    private let output: AsyncStream<PDFVersion>.Continuation
    private var pending: Task<Void, Never>?
    /// Changes still queued when the window closed are ignored.
    private var isStopped = false

    init(url: URL, current: Data, timing: Timing, output: AsyncStream<PDFVersion>.Continuation) {
        self.url = url
        self.current = current
        self.timing = timing
        self.output = output
    }

    /// New versions of the PDF at `url` until the consuming task is cancelled.
    ///
    /// - Parameters:
    ///   - url: The opened file, security-scoped where the platform requires it.
    ///   - current: The bytes that are shown now; an unchanged file yields nothing.
    public static func versions(of url: URL, current: Data, timing: Timing = .standard) -> AsyncStream<PDFVersion> {
        // Only the newest version matters if the consumer falls behind.
        let (versions, output) = AsyncStream.makeStream(of: PDFVersion.self, bufferingPolicy: .bufferingNewest(1))
        let observer = PDFFileObserver(url: url, current: current, timing: timing, output: output)
        let presenter = PDFFilePresenter(url: url)
        let forwarding = Task {
            for await change in presenter.changes {
                await observer.handle(change)
            }
        }
        presenter.start()
        output.onTermination = { _ in
            presenter.stop()
            forwarding.cancel()
            Task { await observer.stop() }
        }
        return versions
    }

    func handle(_ change: PDFFilePresenter.Change) {
        guard !isStopped else { return }
        switch change {
        case .contents:
            break
        case .moved(let newURL):
            // A build that writes elsewhere and moves the result over the PDF also arrives
            // as a move, so the file is read again; a plain rename has unchanged bytes.
            url = newURL
        }
        scheduleReload()
    }

    func stop() {
        isStopped = true
        pending?.cancel()
        pending = nil
        output.finish()
    }

    // MARK: - Private

    /// Debounce: every change restarts the wait, so a burst of writes leads to one read.
    private func scheduleReload() {
        pending?.cancel()
        pending = Task {
            do {
                try await Task.sleep(for: timing.quietPeriod)
            } catch {
                return
            }
            await reload()
        }
    }

    private func reload() async {
        for attempt in 1...max(1, timing.maxAttempts) {
            if attempt > 1 {
                do {
                    try await Task.sleep(for: timing.retryDelay)
                } catch {
                    return
                }
            }
            let data = try? await Self.read(url)
            // A newer change restarted the pipeline; that run reads the newer file.
            if Task.isCancelled { return }
            guard let data, let info = Self.validate(data) else { continue }
            guard data != current else { return }
            current = data
            output.yield(PDFVersion(data: data, info: info))
            return
        }
        // Still incomplete after all attempts: keep showing the loaded version, like the old
        // app did when PDFKit could not open the file. The next change starts over.
    }

    /// Reads the whole file, so the shown version never depends on a file that is being
    /// rewritten. Coordinated, so writers that coordinate (Files app, iCloud) finish first.
    static func read(_ url: URL) async throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
        // The coordinator calls the accessor exactly once on its own queue, so no thread
        // blocks while a writer holds the file.
        let queue = OperationQueue()
        // `NSFileCoordinator` is not Sendable; the mutex hands it to the cancellation handler.
        // Both calls return at once: the read runs later on `queue`.
        let coordinator = Mutex(NSFileCoordinator(filePresenter: nil))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.withLock { coordinator in
                    // Called exactly once, with an error if coordination failed or was cancelled.
                    // `intent.url` is where the file is now, if it moved while the read waited.
                    coordinator.coordinate(with: [intent], queue: queue) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(with: Result { try Data(contentsOf: intent.url) })
                        }
                    }
                }
            }
        } onCancel: {
            // A closed window stops waiting for a writer or an iCloud download.
            coordinator.withLock { $0.cancel() }
        }
    }

    /// The page sizes if `data` is a complete PDF that can be presented.
    ///
    /// PDFKit rejects half-written pdflatex output, but other writers' files can open while
    /// their end is missing, so the `%%EOF` marker is checked as well (#10).
    static func validate(_ data: Data) -> PDFDocumentInfo? {
        guard data.starts(with: Data("%PDF-".utf8)),
              data.suffix(1024).range(of: Data("%%EOF".utf8)) != nil
        else { return nil }
        return try? PDFInspector.inspect(data)
    }
}
