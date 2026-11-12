import CryptoKit
import Foundation
import PDFKit

// PROTOTYPE (issue #10): candidate reload pipeline. Never merged into main.

/// Turns change events into validated PDF versions.
///
/// 1. Debounce: wait until no event arrived for `quietPeriod`.
/// 2. Read the whole file into memory (coordinated, security-scoped), so the loaded
///    document never reads from a file that is being rewritten.
/// 3. Validate: `%PDF-` header, `%%EOF` near the end, PDFKit opens it, at least one page.
///    An incomplete file is retried a few times.
/// 4. Skip versions whose bytes did not change.
public actor ReloadPipeline {
    public struct Version: Sendable {
        public let data: Data
        public let pageCount: Int
        public let digest: String
        /// Read attempts until the file was valid.
        public let attempts: Int
        /// From the first event of the burst to the validated version.
        public let latency: Duration
        public let securityScoped: Bool
    }

    public enum Outcome: Sendable, CustomStringConvertible {
        case reloaded(Version)
        case unchanged(latency: Duration)
        case failed(reason: String, attempts: Int)

        public var description: String {
            switch self {
            case .reloaded(let version):
                "reloaded \(version.pageCount) pages after \(version.latency.milliseconds) ms, \(version.attempts) attempt(s)"
            case .unchanged(let latency):
                "unchanged after \(latency.milliseconds) ms"
            case .failed(let reason, let attempts):
                "failed after \(attempts) attempt(s): \(reason)"
            }
        }
    }

    public struct Settings: Sendable {
        public var quietPeriod: Duration = .milliseconds(300)
        public var retryDelay: Duration = .milliseconds(300)
        public var maxAttempts = 10
        public var requiresEndMarker = true

        public init() {}
    }

    private let url: URL
    private let settings: Settings
    private var lastDigest: String?
    private var burstStart: ContinuousClock.Instant?
    private var pending: Task<Void, Never>?
    private let report: @Sendable (Outcome) -> Void

    public init(url: URL, initialData: Data?, settings: Settings = Settings(), report: @escaping @Sendable (Outcome) -> Void) {
        self.url = url
        self.settings = settings
        self.report = report
        lastDigest = initialData.map(Self.digest)
    }

    /// Call for every change event.
    public func notice(_ event: WatchEvent) {
        if burstStart == nil { burstStart = event.time }
        pending?.cancel()
        pending = Task {
            do {
                try await Task.sleep(for: settings.quietPeriod)
            } catch {
                return
            }
            await load()
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func load() async {
        let start = burstStart ?? .now
        var lastReason = "no attempt"
        for attempt in 1...settings.maxAttempts {
            // A newer event restarted the debounce; that run loads the newer file.
            if Task.isCancelled { return }
            switch Self.readSnapshot(url) {
            case .failure(let reason):
                lastReason = reason.description
            case .success(let snapshot):
                switch Self.validate(snapshot.data, requiresEndMarker: settings.requiresEndMarker) {
                case .failure(let reason):
                    lastReason = reason.description
                case .success(let pageCount):
                    burstStart = nil
                    let digest = Self.digest(snapshot.data)
                    if digest == lastDigest {
                        report(.unchanged(latency: .now - start))
                    } else {
                        lastDigest = digest
                        report(.reloaded(Version(
                            data: snapshot.data, pageCount: pageCount, digest: digest, attempts: attempt,
                            latency: .now - start, securityScoped: snapshot.securityScoped
                        )))
                    }
                    return
                }
            }
            do {
                try await Task.sleep(for: settings.retryDelay)
            } catch {
                return
            }
        }
        burstStart = nil
        report(.failed(reason: lastReason, attempts: settings.maxAttempts))
    }

    // MARK: - Steps, also used by the measurements

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public struct Snapshot: Sendable {
        public let data: Data
        public let securityScoped: Bool
    }

    /// Coordinated, security-scoped read of the whole file.
    public static func readSnapshot(_ url: URL) -> Result<Snapshot, Failure> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Failure> = .failure(Failure(description: "coordinator did not call the reader"))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            do {
                result = .success(try Data(contentsOf: readURL))
            } catch {
                result = .failure(Failure(description: describe(error)))
            }
        }
        if let coordinationError {
            return .failure(Failure(description: "coordination: " + describe(coordinationError)))
        }
        return result.map { Snapshot(data: $0, securityScoped: scoped) }
    }

    public static func validate(_ data: Data, requiresEndMarker: Bool) -> Result<Int, Failure> {
        guard data.count > 16 else { return .failure(Failure(description: "only \(data.count) bytes")) }
        guard data.prefix(5) == Data("%PDF-".utf8) else { return .failure(Failure(description: "no %PDF- header")) }
        if requiresEndMarker, data.suffix(1024).range(of: Data("%%EOF".utf8)) == nil {
            return .failure(Failure(description: "no %%EOF at the end"))
        }
        guard let document = PDFDocument(data: data) else { return .failure(Failure(description: "PDFKit rejected the data")) }
        guard document.pageCount > 0 else { return .failure(Failure(description: "0 pages")) }
        return .success(document.pageCount)
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    public static func describe(_ error: any Error) -> String {
        let error = error as NSError
        var text = "\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (\(underlying.domain) \(underlying.code))"
        }
        return text
    }
}

extension Duration {
    public var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
