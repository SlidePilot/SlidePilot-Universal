import Foundation
import Observation
import PDFKit
import SlidePilotRendering

// PROTOTYPE (issue #10). Debug output in English only, not localized. Never merged into main.

/// Watches one opened PDF with every watcher and reloads it through the candidate pipeline.
@Observable
final class ReloadProbeSession {
    struct LogEntry: Identifiable {
        let id = UUID()
        let milliseconds: Int
        let text: String
    }

    let url: URL
    private(set) var document: PDFDocument?
    private(set) var currentPage = 0
    private(set) var reloadCount = 0
    private(set) var documentGroupDeliveries = 0
    private(set) var log: [LogEntry] = []
    private(set) var selfTestReport: String?
    private(set) var isRunningSelfTest = false

    @ObservationIgnored private let opened = ContinuousClock.now
    @ObservationIgnored private var hub: WatchHub?
    @ObservationIgnored private var pipeline: ReloadPipeline?
    @ObservationIgnored private var consumer: Task<Void, Never>?

    init(url: URL, data: Data) {
        self.url = url
        document = PDFDocument(data: data)
        append("opened: \(document?.pageCount ?? 0) pages, \(data.count) bytes")
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    func start(initialData: Data) {
        guard hub == nil else { return }
        let hub = WatchHub(url: url)
        let pipeline = ReloadPipeline(url: url, initialData: initialData) { [weak self] outcome in
            Task { @MainActor in self?.apply(outcome) }
        }
        self.hub = hub
        self.pipeline = pipeline
        consumer = Task { [weak self] in
            for await event in hub.events {
                self?.append(event.description)
                await pipeline.notice(event)
            }
        }
        hub.start()
        append("watchers started")
    }

    func stop() {
        hub?.stop()
        consumer?.cancel()
        let pipeline = pipeline
        Task { await pipeline?.cancel() }
        hub = nil
    }

    func showPage(_ index: Int) {
        currentPage = min(max(index, 0), max(pageCount - 1, 0))
    }

    /// DocumentGroup handed over a document with different bytes.
    func documentGroupDelivered(digest: String, byteCount: Int) {
        documentGroupDeliveries += 1
        append("DocumentGroup delivered a new version: \(byteCount) bytes, \(digest)")
    }

    func runSelfTest() async {
        isRunningSelfTest = true
        selfTestReport = await Self.selfTest()
        isRunningSelfTest = false
    }

    /// Write-pattern scenarios inside the (sandboxed) app, in its temporary folder.
    static func selfTest() async -> String {
        let folder = FileManager.default.temporaryDirectory
        var parts = [await ReloadScenarios.report(in: folder, title: "\(platformName), in the app (sandboxed), temporary folder")]
        for pattern in [WritePattern.inPlaceChunked, .atomicRename] {
            do {
                parts.append(try await ReloadScenarios.urlBackedReport(pattern: pattern, in: folder))
            } catch {
                parts.append("- \(pattern.rawValue): error \(ReloadPipeline.describe(error))")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Plain-text report without paths or file names.
    var report: String {
        var lines = ["SlidePilot auto-reload probe (issue #10)",
                     "Platform: \(Self.platformName) \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "Pages: \(pageCount), current page: \(currentPage + 1), reloads: \(reloadCount), "
                        + "DocumentGroup deliveries: \(documentGroupDeliveries)",
                     ""]
        lines += log.map { String(format: "%7d ms  ", $0.milliseconds) + $0.text }
        if let selfTestReport {
            lines += ["", selfTestReport]
        }
        return lines.joined(separator: "\n")
    }

    private func apply(_ outcome: ReloadPipeline.Outcome) {
        append("pipeline: \(outcome)" + securityNote(outcome))
        guard case .reloaded(let version) = outcome, let reloaded = PDFDocument(data: version.data) else { return }
        document = reloaded
        reloadCount += 1
        // Keep the page; clamp if the deck got shorter (the old app kept an invalid index).
        showPage(currentPage)
    }

    private func securityNote(_ outcome: ReloadPipeline.Outcome) -> String {
        guard case .reloaded(let version) = outcome else { return "" }
        return version.securityScoped ? " (security-scoped)" : " (no security scope needed)"
    }

    private func append(_ text: String) {
        log.append(LogEntry(milliseconds: (ContinuousClock.now - opened).milliseconds, text: text))
    }

    private static var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iPadOS"
        #endif
    }
}
