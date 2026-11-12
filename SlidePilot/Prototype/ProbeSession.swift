import Foundation
import Observation

// PROTOTYPE (issue #9). Debug output in English only, not localized. Never merged into main.

/// Probe state of one open document window.
@Observable
final class ProbeSession {
    struct Run: Identifiable {
        let id = UUID()
        let context: AccessContext
        let results: [ProbeResult]
    }

    let pdfURL: URL
    let deliveredByteCount: Int
    private(set) var runs: [Run] = []
    private(set) var bookmarkChecks: [ProbeResult] = []
    private(set) var isRunning = false

    init(pdfURL: URL, deliveredByteCount: Int) {
        self.pdfURL = pdfURL
        self.deliveredByteCount = deliveredByteCount
    }

    var folderURL: URL { pdfURL.deletingLastPathComponent() }

    /// First run after opening: document grant only, then a stored folder grant if one covers the PDF.
    func start() async {
        guard runs.isEmpty else { return }
        await probe(folder: nil, context: .documentOnly)
        rememberFile()
        if let stored = GrantStore.folder(containing: pdfURL) {
            await probe(folder: stored.url, context: .storedFolderGrant)
        }
    }

    func grantFolder(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try GrantStore.storeFolder(url)
        } catch {
            appendNote("Store folder bookmark", .failed, FileProbes.describe(error))
        }
        await probe(folder: url, context: .folderGrant)
    }

    /// Resolves the stored PDF bookmarks (run this after relaunching the app) and reads each file.
    func checkStoredBookmarks() {
        var results: [ProbeResult] = []
        for (index, entry) in GrantStore.files().enumerated() {
            let name = "Stored PDF bookmark #\(index + 1)"
            switch entry {
            case .failure(let error):
                results.append(ProbeResult(name: name, outcome: .failed, detail: "resolve: " + FileProbes.describe(error)))
            case .success(let resolved):
                let scoped = resolved.url.startAccessingSecurityScopedResource()
                let read = FileProbes.read(resolved.url, name: name)
                if scoped { resolved.url.stopAccessingSecurityScopedResource() }
                results.append(ProbeResult(name: name, outcome: read.outcome,
                                           detail: "stale \(resolved.isStale), scope \(scoped); " + read.detail))
            }
        }
        for (index, entry) in GrantStore.folders().enumerated() {
            let name = "Stored folder bookmark #\(index + 1)"
            switch entry {
            case .failure(let error):
                results.append(ProbeResult(name: name, outcome: .failed, detail: "resolve: " + FileProbes.describe(error)))
            case .success(let resolved):
                let scoped = resolved.url.startAccessingSecurityScopedResource()
                let listed = (try? FileManager.default.contentsOfDirectory(atPath: resolved.url.path)) != nil
                if scoped { resolved.url.stopAccessingSecurityScopedResource() }
                results.append(ProbeResult(name: name, outcome: listed ? .ok : .failed,
                                           detail: "stale \(resolved.isStale), scope \(scoped), listing \(listed)"))
            }
        }
        if results.isEmpty {
            results.append(ProbeResult(name: "Stored bookmarks", outcome: .notApplicable, detail: "none stored"))
        }
        bookmarkChecks = results
    }

    func clearStoredGrants() {
        GrantStore.clear()
        bookmarkChecks = []
    }

    /// Plain-text report without paths or file names, for pasting into the chat or an issue.
    var report: String {
        var lines = ["SlidePilot file access probe (issue #9)",
                     "Platform: \(platformName) \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "PDF bytes delivered by the document system: \(deliveredByteCount)"]
        for run in runs {
            lines.append("")
            lines.append("## " + run.context.rawValue)
            lines += run.results.map(Self.line)
        }
        if !bookmarkChecks.isEmpty {
            lines.append("")
            lines.append("## stored bookmarks")
            lines += bookmarkChecks.map(Self.line)
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ result: ProbeResult) -> String {
        let mark = switch result.outcome {
        case .ok: "OK  "
        case .failed: "FAIL"
        case .notApplicable: "--  "
        }
        return "\(mark) \(result.name): \(result.detail)"
    }

    private var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iPadOS"
        #endif
    }

    private func probe(folder: URL?, context: AccessContext) async {
        isRunning = true
        let results = await FileProbes.run(pdfURL: pdfURL, folderURL: folder, context: context)
        runs.append(Run(context: context, results: results))
        isRunning = false
    }

    private func rememberFile() {
        let scoped = pdfURL.startAccessingSecurityScopedResource()
        defer { if scoped { pdfURL.stopAccessingSecurityScopedResource() } }
        do {
            try GrantStore.storeFile(pdfURL)
        } catch {
            appendNote("Store PDF bookmark", .failed, FileProbes.describe(error))
        }
    }

    private func appendNote(_ name: String, _ outcome: ProbeResult.Outcome, _ detail: String) {
        runs.append(Run(context: .documentOnly, results: [ProbeResult(name: name, outcome: outcome, detail: detail)]))
    }
}
