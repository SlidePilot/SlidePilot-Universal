import CoreGraphics
import Foundation
import PDFKit
import Synchronization

// PROTOTYPE (issue #10): simulated LaTeX/sync write patterns and measurements. Never merged into main.

/// How a tool replaces the PDF.
public enum WritePattern: String, CaseIterable, Sendable {
    /// pdflatex/lualatex/xelatex (also via latexmk): truncate the existing file, write it in chunks.
    case inPlaceChunked = "in-place, chunked"
    /// Same, with pauses longer than the debounce (slow compile of a large deck).
    case inPlaceSlow = "in-place, slow"
    /// Write a temporary file and rename it over the PDF (`Data.write(.atomic)`, many sync clients, tectonic).
    case atomicRename = "atomic rename"
    /// `FileManager.replaceItemAt` (safe save of NSDocument-based apps).
    case replaceItem = "replaceItemAt"
    /// Delete the PDF, recreate it later (build scripts that clean first).
    case deleteRecreate = "delete + recreate"
    /// Coordinated atomic write (`NSFileCoordinator`, `.forReplacing`), like the Files app or iCloud.
    case coordinatedReplace = "coordinated replace"
    /// Only the modification date changes (`touch`), the bytes stay the same.
    case touchOnly = "touch only"
}

public enum ReloadScenarios {
    public struct Result: Sendable {
        public let pattern: WritePattern
        /// Event kinds per source and phase (1 = first rewrite, 2 = second rewrite).
        public let events: [WatchEvent.Source: [Int: [String]]]
        public let outcomes: [(phase: Int, outcome: ReloadPipeline.Outcome)]
        public let expectedPages: [Int: Int]

        /// The pipeline ended on the right version and never showed a wrong one.
        public var pipelineCorrect: Bool {
            var lastPages = expectedPages[0]
            for (_, outcome) in outcomes {
                guard case .reloaded(let version) = outcome else { continue }
                if !expectedPages.values.contains(version.pageCount) { return false }
                lastPages = version.pageCount
            }
            return lastPages == expectedPages[2]
        }

        public func count(_ source: WatchEvent.Source, phase: Int) -> Int {
            events[source]?[phase]?.count ?? 0
        }
    }

    // MARK: - Test PDFs

    /// A PDF with `pages` pages. `seed` changes the drawing, `strokes` the file size.
    public static func makePDF(pages: Int, seed: Int, strokes: Int = 400) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for page in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(box)
            context.setStrokeColor(CGColor(red: 0.1, green: 0.2, blue: CGFloat(seed % 5) / 5, alpha: 1))
            var value = UInt64(seed * 7919 + page * 104_729 + 1)
            func next() -> CGFloat {
                value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(value >> 33) / CGFloat(1 << 31)
            }
            for _ in 0..<strokes {
                context.move(to: CGPoint(x: next() * 400, y: next() * 300))
                context.addCurve(
                    to: CGPoint(x: next() * 400, y: next() * 300),
                    control1: CGPoint(x: next() * 400, y: next() * 300),
                    control2: CGPoint(x: next() * 400, y: next() * 300)
                )
            }
            context.strokePath()
            // Page marker: `page + 1` filled squares, so each page differs visibly.
            for square in 0...page {
                context.fill(CGRect(x: 10 + square * 14, y: 10, width: 10, height: 10))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Writers

    public static func write(_ data: Data, to url: URL, pattern: WritePattern) async throws {
        let directory = url.deletingLastPathComponent()
        switch pattern {
        case .inPlaceChunked:
            try await writeInPlace(data, to: url, chunks: 8, gap: .milliseconds(40))
        case .inPlaceSlow:
            try await writeInPlace(data, to: url, chunks: 4, gap: .milliseconds(700))
        case .atomicRename:
            try data.write(to: url, options: .atomic)
        case .replaceItem:
            let temporary = directory.appending(path: ".\(UUID().uuidString).pdf")
            try data.write(to: temporary)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        case .deleteRecreate:
            try FileManager.default.removeItem(at: url)
            try await Task.sleep(for: .milliseconds(500))
            try data.write(to: url)
        case .coordinatedReplace:
            var coordinationError: NSError?
            var writeError: (any Error)?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                do {
                    try data.write(to: target, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let error = coordinationError ?? writeError { throw error }
        case .touchOnly:
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
        }
    }

    private static func writeInPlace(_ data: Data, to url: URL, chunks: Int, gap: Duration) async throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        let size = (data.count + chunks - 1) / chunks
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            try handle.write(contentsOf: data[offset..<end])
            try handle.synchronize()
            offset = end
            if offset < data.count { try await Task.sleep(for: gap) }
        }
        try handle.close()
    }

    // MARK: - Scenario runner

    private final class Collector: Sendable {
        /// Current phase and when its write started.
        let phase = Mutex((0, ContinuousClock.now))
        let events = Mutex<[WatchEvent.Source: [Int: [String]]]>([:])
        let outcomes = Mutex<[(phase: Int, outcome: ReloadPipeline.Outcome)]>([])

        func start(phase number: Int) {
            phase.withLock { $0 = (number, .now) }
        }

        func add(_ event: WatchEvent) {
            let (phase, start) = phase.withLock { $0 }
            let entry = "\(event.kind) @\((event.time - start).milliseconds)ms"
            events.withLock { $0[event.source, default: [:]][phase, default: []].append(entry) }
        }

        func add(_ outcome: ReloadPipeline.Outcome) {
            let phase = phase.withLock { $0.0 }
            outcomes.withLock { $0.append((phase, outcome)) }
        }
    }

    /// Opens a 3-page PDF, rewrites it to 5 pages, then to 2 pages, with the same pattern.
    public static func run(_ pattern: WritePattern, in parent: URL, settle: Duration = .seconds(2)) async throws -> Result {
        let directory = parent.appending(path: "reload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "deck.pdf")

        let versions: [Data]
        let expected: [Int: Int]
        if pattern == .touchOnly {
            let same = makePDF(pages: 3, seed: 1)
            versions = [same, same, same]
            expected = [0: 3, 1: 3, 2: 3]
        } else {
            versions = [makePDF(pages: 3, seed: 1), makePDF(pages: 5, seed: 2), makePDF(pages: 2, seed: 3)]
            expected = [0: 3, 1: 5, 2: 2]
        }
        try versions[0].write(to: file)

        let collector = Collector()
        let hub = WatchHub(url: file)
        let pipeline = ReloadPipeline(url: file, initialData: versions[0]) { collector.add($0) }
        let consumer = Task {
            for await event in hub.events {
                collector.add(event)
                await pipeline.notice(event)
            }
        }
        hub.start()
        // Let the presenter register and the poller take its first stamp.
        try await Task.sleep(for: .milliseconds(500))

        for phase in 1...2 {
            collector.start(phase: phase)
            try await write(versions[phase], to: file, pattern: pattern)
            try await Task.sleep(for: settle)
        }

        hub.stop()
        await pipeline.cancel()
        await consumer.value
        return Result(
            pattern: pattern,
            events: collector.events.withLock { $0 },
            outcomes: collector.outcomes.withLock { $0 },
            expectedPages: expected
        )
    }

    /// Runs every pattern and returns a Markdown report.
    public static func report(in parent: URL, title: String) async -> String {
        var lines = ["### \(title)", "",
                     "Events per source in rewrite 1 / rewrite 2 (3 → 5 → 2 pages). Pipeline: debounce 300 ms, full read, %%EOF + PDFKit check.", "",
                     "| Pattern | legacy | vnode | presenter | poll | Pipeline |",
                     "|---|---|---|---|---|---|"]
        var details: [String] = []
        for pattern in WritePattern.allCases {
            do {
                let result = try await run(pattern, in: parent)
                let cells = WatchEvent.Source.allCases.map { "\(result.count($0, phase: 1)) / \(result.count($0, phase: 2))" }
                let reloads = result.outcomes.filter { if case .reloaded = $0.outcome { true } else { false } }.count
                let verdict = result.pipelineCorrect ? "OK" : "WRONG"
                lines.append("| \(pattern.rawValue) | " + cells.joined(separator: " | ") + " | \(verdict), \(reloads) reload(s) |")
                details.append("- **\(pattern.rawValue)**")
                for source in WatchEvent.Source.allCases {
                    let phases = (0...2).map { phase in
                        "\(phase): " + (result.events[source]?[phase]?.joined(separator: ", ") ?? "–")
                    }
                    details.append("  - \(source.rawValue): " + phases.joined(separator: " · "))
                }
                for (phase, outcome) in result.outcomes {
                    details.append("  - pipeline, rewrite \(phase): \(outcome)")
                }
            } catch {
                lines.append("| \(pattern.rawValue) | error: \(ReloadPipeline.describe(error)) | | | | |")
            }
        }
        return (lines + ["", "Details (phase 0 = before the first rewrite):", ""] + details).joined(separator: "\n")
    }

    // MARK: - Partly written files

    /// What PDFKit makes of a file cut off while it is being written.
    public static func truncationReport(_ data: Data, name: String) -> String {
        var lines = ["**\(name)** (\(data.count) bytes, \(PDFDocument(data: data)?.pageCount ?? 0) pages):", "",
                     "| Cut at | %%EOF in tail | PDFKit pages |", "|---|---|---|"]
        let cuts: [(String, Int)] = [0.1, 0.25, 0.5, 0.75, 0.9, 0.99].map { ("\(Int($0 * 100)) %", Int(Double(data.count) * $0)) }
            + [("all but 8 bytes", data.count - 8), ("complete", data.count)]
        for (label, length) in cuts {
            let part = data.prefix(length)
            let marker = part.suffix(1024).range(of: Data("%%EOF".utf8)) != nil
            let pages = PDFDocument(data: part).map { "\($0.pageCount)" } ?? "nil"
            lines.append("| \(label) | \(marker ? "yes" : "no") | \(pages) |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Documents opened by URL

    /// Opens a PDF with `PDFDocument(url:)` (as the old app did), rewrites the file and renders the old document again.
    /// May crash if PDFKit maps the file; run it in its own test.
    public static func urlBackedReport(pattern: WritePattern, in parent: URL) async throws -> String {
        let directory = parent.appending(path: "url-backed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "deck.pdf")
        // Several MB, so PDFKit cannot simply keep the whole small file in one read buffer.
        let original = makePDF(pages: 3, seed: 1, strokes: 40_000)
        try original.write(to: file)

        guard let document = PDFDocument(url: file) else { return "\(pattern.rawValue): PDFDocument(url:) failed" }
        // Render only page 0 before the rewrite, so PDFKit has not parsed the other pages yet.
        let before = (0..<document.pageCount).map { $0 == 0 ? renderDigest(document.page(at: $0)) : "?" }
        try await write(makePDF(pages: 2, seed: 3, strokes: 40_000), to: file, pattern: pattern)
        try await Task.sleep(for: .milliseconds(200))
        let after = (0..<document.pageCount).map { renderDigest(document.page(at: $0)) }
        let fresh = PDFDocument(url: file).map { doc in (0..<doc.pageCount).map { renderDigest(doc.page(at: $0)) } } ?? []
        let reference = PDFDocument(data: original).map { doc in (0..<doc.pageCount).map { renderDigest(doc.page(at: $0)) } } ?? []
        let verdict = after == reference ? "old document still shows the old version"
            : after.contains(where: fresh.contains) ? "old document shows parts of the NEW file"
            : "old document shows something else (damaged)"
        return "- \(pattern.rawValue), \(original.count / 1024) KiB: \(verdict). Pages before \(before), "
            + "after rewrite \(after), expected \(reference), new file \(fresh)"
    }

    private static func renderDigest(_ page: PDFPage?) -> String {
        guard let page else { return "nil page" }
        let width = 80, height = 60
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return "no context" }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bounds = page.bounds(for: .mediaBox)
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        page.draw(with: .mediaBox, to: context)
        guard let bytes = context.data else { return "no data" }
        return ReloadPipeline.digest(Data(bytes: bytes, count: width * height * 4))
    }
}
