import Foundation
import Synchronization

// PROTOTYPE (issue #10): ways to notice that a PDF changed on disk. Never merged into main.

/// One change notification from one watcher.
public struct WatchEvent: Sendable, CustomStringConvertible {
    public enum Source: String, Sendable, CaseIterable {
        /// Old app's `FileObserver`: kqueue on the opened file, `.write` only, never re-opened.
        case legacy
        /// kqueue on the opened file, all vnode events, re-opens the path after delete/rename.
        case vnode
        /// `NSFilePresenter` registered with `NSFileCoordinator`.
        case presenter
        /// Polls `stat()` (inode, size, modification time).
        case poll
    }

    public let source: Source
    public let kind: String
    public let time: ContinuousClock.Instant

    public init(source: Source, kind: String, time: ContinuousClock.Instant = .now) {
        self.source = source
        self.kind = kind
        self.time = time
    }

    public var description: String { "\(source.rawValue):\(kind)" }
}

/// Identity and version of the file at a path.
public struct FileStamp: Sendable, Equatable {
    public let inode: UInt64
    public let size: Int64
    public let modifiedNanoseconds: Int64

    public static func current(_ url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path(percentEncoded: false), &info) == 0 else { return nil }
        let mtime = info.st_mtimespec
        return FileStamp(
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedNanoseconds: Int64(mtime.tv_sec) * 1_000_000_000 + Int64(mtime.tv_nsec)
        )
    }
}

/// kqueue (dispatch source) watcher on the file's descriptor.
///
/// `@unchecked Sendable`: all mutable state is only touched on `queue`.
public final class VnodeWatcher: @unchecked Sendable {
    private let url: URL
    private let source: WatchEvent.Source
    private let mask: DispatchSource.FileSystemEvent
    private let reopensAfterReplace: Bool
    private let emit: @Sendable (WatchEvent) -> Void
    private let queue = DispatchQueue(label: "reload-probe.vnode")
    private var dispatchSource: (any DispatchSourceFileSystemObject)?
    private var isCancelled = false

    /// The old app's observer: `.write` only, no re-open.
    public static func legacy(url: URL, emit: @escaping @Sendable (WatchEvent) -> Void) -> VnodeWatcher {
        VnodeWatcher(url: url, source: .legacy, mask: .write, reopensAfterReplace: false, emit: emit)
    }

    /// All events, re-opens the path when the watched inode goes away.
    public static func full(url: URL, emit: @escaping @Sendable (WatchEvent) -> Void) -> VnodeWatcher {
        VnodeWatcher(url: url, source: .vnode, mask: .all, reopensAfterReplace: true, emit: emit)
    }

    private init(
        url: URL,
        source: WatchEvent.Source,
        mask: DispatchSource.FileSystemEvent,
        reopensAfterReplace: Bool,
        emit: @escaping @Sendable (WatchEvent) -> Void
    ) {
        self.url = url
        self.source = source
        self.mask = mask
        self.reopensAfterReplace = reopensAfterReplace
        self.emit = emit
    }

    public func start() {
        queue.async { self.attach(attempt: 0) }
    }

    public func cancel() {
        queue.async {
            self.isCancelled = true
            self.dispatchSource?.cancel()
            self.dispatchSource = nil
        }
    }

    private func attach(attempt: Int) {
        guard !isCancelled else { return }
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            let code = errno
            // After delete + recreate the new file may appear later; retry for up to 5 s.
            if reopensAfterReplace, attempt < 50 {
                queue.asyncAfter(deadline: .now() + .milliseconds(100)) { self.attach(attempt: attempt + 1) }
            } else {
                emit(WatchEvent(source: source, kind: "open failed (errno \(code))"))
            }
            return
        }
        if attempt > 0 {
            emit(WatchEvent(source: source, kind: "reopened after \(attempt) retries"))
        }
        let watched = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: queue)
        watched.setEventHandler { [weak self, weak watched] in
            guard let self, let watched else { return }
            let events = watched.data
            self.emit(WatchEvent(source: self.source, kind: Self.describe(events)))
            if self.reopensAfterReplace, !events.isDisjoint(with: [.delete, .rename, .revoke]) {
                watched.cancel()
                self.dispatchSource = nil
                self.attach(attempt: 0)
            }
        }
        watched.setCancelHandler { close(descriptor) }
        dispatchSource = watched
        watched.resume()
    }

    private static func describe(_ events: DispatchSource.FileSystemEvent) -> String {
        let names: [(DispatchSource.FileSystemEvent, String)] = [
            (.write, "write"), (.extend, "extend"), (.attrib, "attrib"), (.delete, "delete"),
            (.rename, "rename"), (.revoke, "revoke"), (.link, "link"), (.funlock, "funlock"),
        ]
        let present = names.filter { events.contains($0.0) }.map(\.1)
        return present.isEmpty ? "raw \(events.rawValue)" : present.joined(separator: "+")
    }
}

/// `NSFilePresenter` for the PDF, as UIDocument/NSDocument use it.
public final class PresenterWatcher: NSObject, NSFilePresenter, Sendable {
    public let presentedItemOperationQueue: OperationQueue
    private let currentURL: Mutex<URL>
    private let emit: @Sendable (WatchEvent) -> Void

    public init(url: URL, emit: @escaping @Sendable (WatchEvent) -> Void) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        currentURL = Mutex(url)
        self.emit = emit
    }

    public var presentedItemURL: URL? { currentURL.withLock { $0 } }

    public func start() { NSFileCoordinator.addFilePresenter(self) }
    public func cancel() { NSFileCoordinator.removeFilePresenter(self) }

    public func presentedItemDidChange() {
        emit(WatchEvent(source: .presenter, kind: "didChange"))
    }

    public func presentedItemDidMove(to newURL: URL) {
        currentURL.withLock { $0 = newURL }
        emit(WatchEvent(source: .presenter, kind: "didMove"))
    }

    public func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        emit(WatchEvent(source: .presenter, kind: "deletion"))
        completionHandler(nil)
    }

    public func presentedItemDidGain(_ version: NSFileVersion) {
        emit(WatchEvent(source: .presenter, kind: "didGainVersion"))
    }

    public func presentedItemDidLose(_ version: NSFileVersion) {
        emit(WatchEvent(source: .presenter, kind: "didLoseVersion"))
    }

    public func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        emit(WatchEvent(source: .presenter, kind: "didResolveConflict"))
    }

    public func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) {
        emit(WatchEvent(source: .presenter, kind: "ubiquityAttributes(\(attributes.count))"))
    }
}

/// Polls the path's `stat()` and reports inode, size and modification time changes.
public enum PollWatcher {
    public static func start(
        url: URL,
        interval: Duration,
        emit: @escaping @Sendable (WatchEvent) -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            var last = FileStamp.current(url)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let now = FileStamp.current(url)
                guard now != last else { continue }
                let kind: String
                switch (last, now) {
                case (_, nil): kind = "missing"
                case (nil, _): kind = "appeared"
                case let (old?, new?) where old.inode != new.inode: kind = "new inode"
                case let (old?, new?) where old.size != new.size: kind = "size"
                default: kind = "mtime"
                }
                last = now
                emit(WatchEvent(source: .poll, kind: kind))
            }
        }
    }
}

/// Runs all watchers on one URL and forwards their events as one stream.
public final class WatchHub: Sendable {
    public let events: AsyncStream<WatchEvent>
    private let continuation: AsyncStream<WatchEvent>.Continuation
    private let legacy: VnodeWatcher
    private let vnode: VnodeWatcher
    private let presenter: PresenterWatcher
    private let poll = Mutex<Task<Void, Never>?>(nil)
    private let url: URL
    private let pollInterval: Duration

    public init(url: URL, pollInterval: Duration = .milliseconds(250)) {
        let (stream, continuation) = AsyncStream.makeStream(of: WatchEvent.self)
        events = stream
        self.continuation = continuation
        self.url = url
        self.pollInterval = pollInterval
        // The watchers capture only Sendable values, not `self`.
        let sink: @Sendable (WatchEvent) -> Void = { event in
            continuation.yield(event)
        }
        legacy = .legacy(url: url, emit: sink)
        vnode = .full(url: url, emit: sink)
        presenter = PresenterWatcher(url: url, emit: sink)
    }

    public func start() {
        legacy.start()
        vnode.start()
        presenter.start()
        let task = PollWatcher.start(url: url, interval: pollInterval) { [continuation] in continuation.yield($0) }
        poll.withLock { $0 = task }
    }

    public func stop() {
        legacy.cancel()
        vnode.cancel()
        presenter.cancel()
        poll.withLock { $0?.cancel() }
        continuation.finish()
    }
}
