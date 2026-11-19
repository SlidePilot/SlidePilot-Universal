import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import SlidePilotRendering

/// Reads a file from the repository's `Fixtures/` folder (tests run unhosted).
private func fixtureData(_ name: String, filePath: String = #filePath) throws -> Data {
    let root = URL(filePath: filePath)
        .deletingLastPathComponent() // SlidePilotRenderingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SlidePilotRendering
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
    return try Data(contentsOf: root.appending(path: "Fixtures/\(name)"))
}

/// A one-page PDF of 400 × 300 pt written by hand, so tests control the raw annotation
/// dictionaries that LaTeX writes and PDFKit does not describe.
private func rawPDF(rotation: Int = 0, annotations: [String]) throws -> Data {
    let annotationRefs = annotations.indices.map { "\($0 + 4) 0 R" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Rotate \(rotation) /Annots [\(annotationRefs)] >>",
    ]
    objects += annotations.map { "<< /Type /Annot \($0) >>" }
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(pdf.utf8.count)
        pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    pdf += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    return Data(pdf.utf8)
}

private func cache(_ data: Data) throws -> RenderCache {
    RenderCache(data: data, info: try PDFInspector.inspect(data))
}

private func isClose(_ first: CGRect, _ second: CGRect) -> Bool {
    abs(first.minX - second.minX) < 0.001 && abs(first.minY - second.minY) < 0.001
        && abs(first.width - second.width) < 0.001 && abs(first.height - second.height) < 0.001
}

@Suite struct SlideMovieTests {
    /// `\movie` from the multimedia package; PDFKit on macOS 27 hides its `/Movie` entry.
    @Test func readsTheMovieOfTheFixture() async throws {
        let cache = try cache(try fixtureData("media.pdf"))
        let movies = await cache.movies(page: 1)
        let movie = try #require(movies.first)
        #expect(movies.count == 1)
        #expect(movie.reference == "media/test-pattern.mp4")
        // /Rect [90.709 63.409 272.126 214.305] on a 362.835 × 272.126 pt page.
        #expect(isClose(movie.unitRect, CGRect(x: 0.25, y: 0.21247, width: 0.5, height: 0.55451)))
        #expect(await cache.movies(page: 0).isEmpty)
        #expect(await cache.movies(page: 99).isEmpty)
    }

    @Test func readsRunLinksOfTheFixtureAsFiles() async throws {
        let links = try await cache(fixtureData("media.pdf")).links(page: 2)
        let files = links.compactMap { if case .file(let file) = $0.target { file } else { nil } }
        #expect(files == ["media/test-pattern.mp4", "plain-slides.pdf"])
        // PDFKit reports them as URL actions too; they must not show up twice.
        #expect(!links.contains { if case .url(let url) = $0.target { url.isFileURL || url.scheme == nil } else { false } })
    }

    @Test func listsEveryLinkedFileOnce() async throws {
        let references = try await cache(fixtureData("media.pdf")).linkedFileReferences()
        #expect(references == ["media/test-pattern.mp4", "plain-slides.pdf"])
        let none = try await cache(fixtureData("links.pdf")).linkedFileReferences()
        #expect(none.isEmpty)
    }

    @Test func readsFileSpecificationDictionaries() async throws {
        let data = try rawPDF(annotations: [
            "/Subtype /Movie /Rect [0 0 200 150] /Movie << /F << /Type /Filespec /F (old.mp4) /UF (new video.mp4) >> >>",
            "/Subtype /Link /Rect [200 150 400 300] /A << /S /Launch /F << /Type /Filespec /F (talk.key) >> >>",
            "/Subtype /Link /Rect [0 150 100 300] /A << /S /Launch /Unix (unix.pdf) >>",
            "/Subtype /Link /Rect [100 150 200 300] /A << /S /Launch /Mac << /F (mac.pdf) >> >>",
        ])
        let cache = try cache(data)
        #expect(await cache.movies(page: 0).map(\.reference) == ["new video.mp4"])
        let files = await cache.links(page: 0).compactMap { if case .file(let file) = $0.target { file } else { nil } }
        #expect(files == ["talk.key", "unix.pdf", "mac.pdf"])
    }

    @Test func skipsMoviesWithoutAFileAndOtherLaunchTargets() async throws {
        let data = try rawPDF(annotations: [
            "/Subtype /Movie /Rect [0 0 200 150] /Movie << /Aspect [320 180] >>",
            "/Subtype /Movie /Rect [0 0 200 150]",
            "/Subtype /Link /Rect [0 0 10 10] /A << /S /Launch >>",
            "/Subtype /Screen /Rect [0 0 200 150]",
        ])
        let cache = try cache(data)
        #expect(await cache.movies(page: 0).isEmpty)
        #expect(await cache.links(page: 0).isEmpty)
        #expect(await cache.linkedFileReferences().isEmpty)
    }

    /// Writers may give the corners of `/Rect` in any order.
    @Test func normalizesReversedRects() async throws {
        let data = try rawPDF(annotations: ["/Subtype /Movie /Rect [200 300 0 150] /Movie << /F (a.mp4) >>"])
        let movie = try #require(await cache(data).movies(page: 0).first)
        #expect(isClose(movie.unitRect, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
    }

    /// The video turns with the page, like the links (DEF-19).
    @Test(arguments: [
        (0, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
        (90, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        (180, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        (270, CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
    ])
    func followsThePageRotation(rotation: Int, expected: CGRect) async throws {
        let data = try rawPDF(rotation: rotation, annotations: ["/Subtype /Movie /Rect [0 0 200 150] /Movie << /F (a.mp4) >>"])
        let movie = try #require(await cache(data).movies(page: 0).first)
        #expect(isClose(movie.unitRect, expected))
    }

    @Test func placesTheMovieInARegionWithoutClipping() {
        let movie = SlideMovie(unitRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), reference: "a.mp4")
        #expect(movie.unitRect(in: .full) == movie.unitRect)
        #expect(movie.unitRect(in: .leftHalf) == CGRect(x: 0.5, y: 0.25, width: 1, height: 0.5))
        #expect(movie.unitRect(in: .rightHalf) == CGRect(x: -0.5, y: 0.25, width: 1, height: 0.5))
        let notesSide = SlideMovie(unitRect: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3), reference: "a.mp4")
        #expect(notesSide.unitRect(in: .leftHalf) == nil)
    }
}
