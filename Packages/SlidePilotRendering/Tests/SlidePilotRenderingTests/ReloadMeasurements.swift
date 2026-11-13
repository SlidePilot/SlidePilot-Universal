import Foundation
import SlidePilotRendering
import Testing

// PROTOTYPE (issue #10): measurements for auto-reload. Never merged into main.
// Reports are recorded as test attachments and printed.

@Suite(.serialized)
struct ReloadMeasurements {
    private var platform: String {
        #if os(macOS)
        "macOS, package test (not sandboxed)"
        #else
        "iPadOS simulator, package test"
        #endif
    }

    @Test(.timeLimit(.minutes(3)))
    func writePatterns() async throws {
        let report = await ReloadScenarios.report(in: FileManager.default.temporaryDirectory, title: platform)
        Self.publish(report, name: "reload-write-patterns")
    }

    @Test
    func truncatedFiles() throws {
        var parts = [ReloadScenarios.truncationReport(ReloadScenarios.makePDF(pages: 5, seed: 2), name: "Core Graphics PDF")]
        for fixture in ["plain-slides.pdf", "large-deck.pdf"] {
            let data = try Data(contentsOf: Self.fixtures.appending(path: fixture))
            parts.append(ReloadScenarios.truncationReport(data, name: "pdflatex fixture \(fixture)"))
        }
        Self.publish(parts.joined(separator: "\n\n"), name: "reload-truncation")
    }

    @Test(arguments: [WritePattern.inPlaceChunked, .atomicRename])
    func urlBackedDocument(pattern: WritePattern) async throws {
        let report = try await ReloadScenarios.urlBackedReport(pattern: pattern, in: FileManager.default.temporaryDirectory)
        Self.publish(report, name: "reload-url-backed")
    }

    /// Does a bookmark of the PDF still resolve after the file was replaced?
    @Test(arguments: WritePattern.allCases.filter { $0 != .touchOnly })
    func bookmarkAfterRewrite(pattern: WritePattern) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "bookmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "deck.pdf")
        try ReloadScenarios.makePDF(pages: 3, seed: 1).write(to: file)
        let bookmark = try file.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        let inodeBefore = FileStamp.current(file)?.inode

        try await ReloadScenarios.write(ReloadScenarios.makePDF(pages: 5, seed: 2), to: file, pattern: pattern)

        var stale = false
        let line: String
        do {
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let samePath = resolved.standardizedFileURL.resolvingSymlinksInPath() == file.standardizedFileURL.resolvingSymlinksInPath()
            line = "- \(pattern.rawValue): resolves, same path \(samePath), stale \(stale), new inode \(inodeBefore != FileStamp.current(file)?.inode)"
        } catch {
            line = "- \(pattern.rawValue): does NOT resolve (\(ReloadPipeline.describe(error)))"
        }
        Self.publish(line, name: "reload-bookmark")
    }

    private static var repository: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var fixtures: URL {
        repository.appending(path: "Fixtures", directoryHint: .isDirectory)
    }

    /// Records the report and also writes it to the git-ignored `build/reload-reports/`,
    /// because the result bundle stores text attachments compressed.
    private static func publish(_ report: String, name: String) {
        Attachment.record(report, named: "\(name).md")
        #if os(macOS)
        let suffix = "mac"
        #else
        let suffix = "ipad-sim"
        #endif
        let folder = repository.appending(path: "build/reload-reports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name)-\(suffix).md")
        let previous = (try? String(contentsOf: file, encoding: .utf8)).map { $0 + "\n\n" } ?? ""
        try? (previous + report).write(to: file, atomically: true, encoding: .utf8)
    }
}
