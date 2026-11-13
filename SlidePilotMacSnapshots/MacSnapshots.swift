import PDFKit
import Testing
@testable import SlidePilot

/// Mac screenshots for PRs, rendered by the app itself (see `WindowSnapshot`).
///
/// Not part of the default test plan. Run the `SlidePilotMacSnapshots` scheme and
/// export the PNGs with `scripts/export-mac-snapshots.py`.
/// Use fixtures only, never personal documents.
@Suite(.serialized)
struct MacSnapshots {
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func firstSlide(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        try await WindowSnapshot.record(DocumentView(document: document), name: "slides-first", appearance: appearance)
    }

    // LAY-09: after the last slide the preview shows the end-of-deck page.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func lastSlide(appearance: WindowSnapshot.Appearance) async throws {
        let data = try Fixture.data("plain-slides.pdf")
        let pdf = try #require(PDFDocument(data: data))
        let document = try PDFFileDocument(data: data)
        let view = DocumentView(document: document, page: pdf.pageCount - 1)
        try await WindowSnapshot.record(view, name: "slides-last", appearance: appearance)
    }

    // DOC-08: a copy of a 6-page deck is open on slide 6 and is rewritten in place with a
    // 4-page deck (like pdflatex), then replaced atomically with the 6-page deck again.
    // Expected: slide 4 of 4 with the end-of-deck page, then slide 4 of 6 with slide 5 next.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func reloadAfterRecompile(appearance: WindowSnapshot.Appearance) async throws {
        let long = try Fixture.data("rotated.pdf")
        let short = try Fixture.data("media.pdf")
        let folder = FileManager.default.temporaryDirectory.appending(path: "reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "slides.pdf")
        try long.write(to: url)

        let view = DocumentView(document: try PDFFileDocument(data: long), fileURL: url, page: 5)
        let window = WindowSnapshot.makeWindow(view, appearance: appearance)
        defer { window.close() }
        // Let the file presenter register before the first change.
        try await Task.sleep(for: .seconds(1))

        try short.write(to: url)
        try await Task.sleep(for: .seconds(4))
        try await WindowSnapshot.record(window, name: "reload-shorter-\(appearance.rawValue)")

        try long.write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(4))
        try await WindowSnapshot.record(window, name: "reload-longer-\(appearance.rawValue)")
    }
}
