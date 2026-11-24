import CoreGraphics
import Foundation
import PDFKit
import SlidePilotCore
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
/// dictionaries that LaTeX writes and PDFKit does not describe. Annotations are objects 4,
/// 5, …; `extraObjects` follow them, and `pageEntries` go into the page dictionary.
private func rawPDF(rotation: Int = 0, pageEntries: String = "", annotations: [String], extraObjects: [String] = []) throws -> Data {
    let annotationRefs = annotations.indices.map { "\($0 + 4) 0 R" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Rotate \(rotation) /Annots [\(annotationRefs)] \(pageEntries) >>",
    ]
    objects += annotations.map { "<< /Type /Annot \($0) >>" }
    objects += extraObjects
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
        #expect(isClose(movie.bounds, CGRect(x: 90.709, y: 63.409, width: 181.417, height: 150.896)))
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
        let movie = SlideMovie(unitRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), bounds: .zero, reference: "a.mp4")
        #expect(movie.unitRect(in: .full) == movie.unitRect)
        #expect(movie.unitRect(in: .leftHalf) == CGRect(x: 0.5, y: 0.25, width: 1, height: 0.5))
        #expect(movie.unitRect(in: .rightHalf) == CGRect(x: -0.5, y: 0.25, width: 1, height: 0.5))
        let notesSide = SlideMovie(unitRect: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3), bounds: .zero, reference: "a.mp4")
        #expect(notesSide.unitRect(in: .leftHalf) == nil)
    }

    // MARK: - Activation (#139)

    /// Beamer's `autostart`, `loop`, `repeat`, `palindrome`, `start` and `duration`.
    @Test func readsTheActivationOfTheFixture() async throws {
        let cache = try cache(try fixtureData("video-options.pdf"))
        func activation(_ page: Int) async throws -> MovieActivation {
            let movies = await cache.movies(page: page)
            #expect(movies.count == 1)
            return try #require(movies.first).activation
        }
        #expect(try await activation(1) == MovieActivation())
        #expect(try await activation(2) == MovieActivation(autostarts: true))
        #expect(try await activation(3) == MovieActivation(mode: .repeat, autostarts: true))
        #expect(try await activation(4) == MovieActivation(mode: .repeat))
        #expect(try await activation(5) == MovieActivation(mode: .palindrome, autostarts: true))
        #expect(try await activation(6) == MovieActivation(start: 1, duration: 2, autostarts: true))
        // The video over three overlay steps autostarts and loops on each of them.
        for page in 7...9 {
            #expect(try await activation(page) == MovieActivation(mode: .repeat, autostarts: true))
        }
        #expect(await cache.movies(page: 1).first?.reference == "media/test-pattern.mp4")
        #expect(await cache.linkedFileReferences() == ["media/test-pattern.mp4"])
    }

    /// The overlay steps of one frame place the video at the same place (#140).
    @Test func buildStepsOfTheFixtureShareTheVideoBounds() async throws {
        let cache = try cache(try fixtureData("video-options.pdf"))
        var bounds: [CGRect] = []
        for page in 7...9 {
            bounds.append(try #require(await cache.movies(page: page).first).bounds)
        }
        #expect(bounds[0].width > 0)
        #expect(bounds.allSatisfy { isClose($0, bounds[0]) })
    }

    /// pdfTeX route: a hidden widget runs the movie action when the page opens.
    @Test func autostartsFromAWidgetPageOpenAction() async throws {
        let data = try rawPDF(annotations: [
            "/Subtype /Movie /T (clip) /Rect [0 0 200 150] /Movie << /F (a.mp4) >> /A << >>",
            "/Subtype /Movie /T (other) /Rect [200 0 400 150] /Movie << /F (b.mp4) >>",
            "/Subtype /Widget /FT /Btn /Rect [0 0 0 0] /T (wid@clip) /AA << /PO 7 0 R >>",
        ], extraObjects: ["<< /S /Movie /T (clip) /Operation /Play >>"])
        let movies = try await cache(data).movies(page: 0)
        #expect(movies.map(\.activation.autostarts) == [true, false])
    }

    /// pdfmark route: the page's own open action; an omitted operation means Play.
    @Test func autostartsFromThePageOpenAction() async throws {
        let data = try rawPDF(
            pageEntries: "/AA << /O << /S /Movie /T (clip) >> >>",
            annotations: ["/Subtype /Movie /T (clip) /Rect [0 0 200 150] /Movie << /F (a.mp4) >>"]
        )
        #expect(try await cache(data).movies(page: 0).first?.activation.autostarts == true)
    }

    /// A movie action may name its annotation instead of a title, and may follow another
    /// action through `/Next`.
    @Test func autostartsByAnnotationReferenceAndNextAction() async throws {
        let data = try rawPDF(
            pageEntries: "/AA << /O << /S /JavaScript /JS () /Next [<< /S /Movie /Annotation 4 0 R >>] >> >>",
            annotations: [
                "/Subtype /Movie /Rect [0 0 200 150] /Movie << /F (a.mp4) >>",
                "/Subtype /Movie /Rect [200 0 400 150] /Movie << /F (b.mp4) >>",
            ]
        )
        let movies = try await cache(data).movies(page: 0)
        #expect(movies.map(\.activation.autostarts) == [true, false])
    }

    /// Stop, Pause and Resume on page open do not start a video, and an action for another
    /// title leaves the movie alone.
    @Test(arguments: ["/Operation /Stop", "/Operation /Pause", "/Operation /Resume", "/T (else) /Operation /Play"])
    func otherOperationsDoNotAutostart(_ entries: String) async throws {
        let title = entries.contains("/T ") ? "" : "/T (clip)"
        let data = try rawPDF(
            pageEntries: "/AA << /O << /S /Movie \(title) \(entries) >> >>",
            annotations: ["/Subtype /Movie /T (clip) /Rect [0 0 200 150] /Movie << /F (a.mp4) >>"]
        )
        #expect(try await cache(data).movies(page: 0).first?.activation.autostarts == false)
    }

    @Test(arguments: [
        ("/A << /Mode /Once >>", MovieActivation()),
        ("/A << /Mode /Open >>", MovieActivation(mode: .open)),
        ("/A << /Mode /Repeat >>", MovieActivation(mode: .repeat)),
        ("/A << /Mode /Palindrome >>", MovieActivation(mode: .palindrome)),
        ("/A << /Mode /Unknown >>", MovieActivation()),
        ("/A true", MovieActivation()),
        ("", MovieActivation()),
        // Beamer: start=5s, duration=2.5s.
        ("/A << /Start [640 128] /Duration [320 128] >>", MovieActivation(start: 5, duration: 2.5)),
        // A plain number, and an 8-byte integer string with a scale of 10 (3 s).
        ("/A << /Start 2 /Duration [<000000000000001E> 10] >>", MovieActivation(start: 2, duration: 3)),
        // Malformed times are ignored.
        ("/A << /Start [1 2 3] /Duration (x) >>", MovieActivation()),
    ])
    func readsModeStartAndDuration(_ entries: String, expected: MovieActivation) async throws {
        let data = try rawPDF(annotations: ["/Subtype /Movie /Rect [0 0 200 150] /Movie << /F (a.mp4) >> \(entries)"])
        #expect(try await cache(data).movies(page: 0).first?.activation == expected)
    }
}

// MARK: - Videos stored inside the PDF (#142)

@Suite struct EmbeddedMovieTests {
    private func makeStore() -> (EmbeddedFileStore, parent: URL) {
        let parent = FileManager.default.temporaryDirectory.appending(path: "EmbeddedMovieTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (EmbeddedFileStore(parent: parent), parent)
    }

    private func cache(_ name: String, store: EmbeddedFileStore) throws -> RenderCache {
        let data = try fixtureData(name)
        return RenderCache(data: data, info: try PDFInspector.inspect(data), embeddedFiles: store)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func writesTheEmbeddedVideoOfTheFixtureToATemporaryFile() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let cache = try cache("media-embedded.pdf", store: store)
        let movies = await cache.movies(page: 1)
        #expect(movies.count == 1)
        let movie = try #require(movies.first)
        #expect(movie.reference == "test-pattern.mp4")
        #expect(movie.fileName == "test-pattern.mp4")
        #expect(movie.activation == MovieActivation())
        let file = try #require(movie.embeddedFile)
        #expect(file.pathExtension == "mp4")
        #expect(file.deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL)
        #expect(try Data(contentsOf: file) == fixtureData("media/test-pattern.mp4"))
    }

    /// Both overlay steps embed the same video, so they share the file and the player (#140).
    @Test func buildStepsShareTheFile() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let cache = try cache("media-embedded.pdf", store: store)
        let plain = try #require(await cache.movies(page: 1).first)
        let first = try #require(await cache.movies(page: 2).first)
        let second = try #require(await cache.movies(page: 3).first)
        #expect(first.activation == MovieActivation(mode: .repeat, autostarts: true))
        #expect(second.activation == first.activation)
        #expect(isClose(first.bounds, second.bounds))
        #expect(first.embeddedFile == plain.embeddedFile)
        #expect(second.embeddedFile == plain.embeddedFile)
        #expect(await store.files.count == 1)
    }

    /// An embedded video never asks for folder access.
    @Test func embeddedVideosAreNoLinkedFiles() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        #expect(try await cache("media-embedded.pdf", store: store).linkedFileReferences().isEmpty)
    }

    /// A reload that no longer embeds the video removes its file; one that still does keeps it.
    @Test func reloadRemovesFilesThePDFNoLongerStores() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let file = try #require(await cache("media-embedded.pdf", store: store).movies(page: 1).first?.embeddedFile)

        let same = try cache("media-embedded.pdf", store: store)
        await same.removeUnusedEmbeddedFiles()
        #expect(exists(file))
        #expect(await same.movies(page: 1).first?.embeddedFile == file)

        await (try cache("media.pdf", store: store)).removeUnusedEmbeddedFiles()
        #expect(!exists(file))
        #expect(await store.files.isEmpty)
    }

    /// Closing the document empties the store and removes its folder.
    @Test func closingTheDocumentRemovesTheFiles() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let cache = try cache("media-embedded.pdf", store: store)
        let file = try #require(await cache.movies(page: 1).first?.embeddedFile)
        #expect(exists(file))
        // What closing the document does (PresentationSession.documentClosed).
        await store.removeAll()
        #expect(!exists(store.directory))
    }

    /// A temporary copy that went away (closed document, system cleanup) is written again
    /// the next time the page's videos are asked for.
    @Test func writesARemovedFileAgain() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let cache = try cache("media-embedded.pdf", store: store)
        let file = try #require(await cache.movies(page: 1).first?.embeddedFile)
        await store.removeAll()
        #expect(!exists(file))
        #expect(await cache.movies(page: 1).first?.embeddedFile == file)
        #expect(exists(file))
    }

    /// Without an extension in the name, the stream's MIME type gives one; `/EF /UF` wins
    /// over `/EF /F`.
    @Test func takesTheExtensionFromTheMIMEType() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let data = try rawPDF(
            annotations: ["/Subtype /Movie /Rect [0 0 200 150] /Movie << /F << /Type /Filespec /UF (clip) /EF << /F 6 0 R /UF 5 0 R >> >> >>"],
            extraObjects: [
                "<< /Type /EmbeddedFile /Subtype /video#2Fquicktime /Length 7 >>\nstream\nunicode\nendstream",
                "<< /Type /EmbeddedFile /Length 5 >>\nstream\nplain\nendstream",
            ]
        )
        let cache = RenderCache(data: data, info: try PDFInspector.inspect(data), embeddedFiles: store)
        let movie = try #require(await cache.movies(page: 0).first)
        let file = try #require(movie.embeddedFile)
        #expect(file.pathExtension == "mov")
        #expect(try Data(contentsOf: file) == Data("unicode".utf8))
        #expect(movie.reference == "clip")
    }

    /// A broken embedded stream keeps the poster; it never looks for a file of that name.
    @Test func skipsEmbeddedVideosThatCannotBeRead() async throws {
        let (store, parent) = makeStore()
        defer { EmbeddedFileStore.removeLeftovers(in: parent) }
        let data = try rawPDF(
            annotations: ["/Subtype /Movie /Rect [0 0 200 150] /Movie << /F << /Type /Filespec /F (a.mp4) /EF << /F 5 0 R >> >> >>"],
            extraObjects: ["<< /Type /EmbeddedFile /Length 0 >>\nstream\n\nendstream"]
        )
        let cache = RenderCache(data: data, info: try PDFInspector.inspect(data), embeddedFiles: store)
        #expect(await cache.movies(page: 0).isEmpty)
        #expect(await cache.linkedFileReferences().isEmpty)
    }
}
