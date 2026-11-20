import CoreGraphics
import Foundation
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

@Suite struct SplitNotesTests {
    // NOTES-02: the audience sees the half opposite the notes.
    @Test(arguments: [
        (NotesPosition.none, PageRegion.full, PageRegion.full),
        (.right, .leftHalf, .rightHalf),
        (.left, .rightHalf, .leftHalf),
        (.bottom, .topHalf, .bottomHalf),
        (.top, .bottomHalf, .topHalf),
    ])
    func regions(_ position: NotesPosition, _ audience: PageRegion, _ notes: PageRegion) {
        #expect(PageRegion.audience(position) == audience)
        #expect(PageRegion.notes(position) == notes)
    }

    // NOTES-03: the fixtures' keywords open in Split mode at that position.
    @Test(arguments: [
        ("keyword-sp-right.pdf", NotesPosition.right),
        ("keyword-sp-left.pdf", .left),
        ("keyword-sp-top.pdf", .top),
        ("keyword-sp-bottom.pdf", .bottom),
    ])
    func detectsFixtureKeyword(_ file: String, _ position: NotesPosition) throws {
        let info = try PDFInspector.inspect(fixtureData(file))
        #expect(NotesDisplay(pdfKeywords: info.keywords) == NotesDisplay(mode: .split, position: position))
    }

    // Keywords are case-sensitive; decks without a keyword open as text notes.
    @Test(arguments: ["keyword-lowercase.pdf", "notes-right.pdf", "plain-slides.pdf"])
    func ignoresFixtureWithoutKeyword(_ file: String) throws {
        let info = try PDFInspector.inspect(fixtureData(file))
        #expect(NotesDisplay(pdfKeywords: info.keywords) == .default)
    }

    // "Beamer, SP-Left" is one string in the PDF; PDFKit splits it at the comma.
    @Test func mixedKeywordEntry() throws {
        let info = try PDFInspector.inspect(fixtureData("keyword-mixed.pdf"))
        #expect(NotesPosition(pdfKeywords: info.keywords) == .left, "keywords: \(info.keywords)")
    }

    // NOTES-02: the halves of a rotated page are measured as displayed, so the audience
    // half shows the slide on every page of the rotated fixture.
    @Test func rotatedPagesSplitAsDisplayed() async throws {
        let data = try fixtureData("rotated-notes-right.pdf")
        let info = try PDFInspector.inspect(data)
        let cache = RenderCache(data: data, info: info)
        for page in 0..<info.pageCount {
            let size = info.pageSizes[page]
            #expect(size.width > size.height, "page \(page + 1) is displayed in landscape")
            let audience = try await cache.image(page: page, region: .audience(.right), fitting: PixelSize(width: 400, height: 400))
            #expect(audience.region == .leftHalf)
            #expect(abs(Double(audience.image.width) / Double(audience.image.height) - size.width / 2 / size.height) < 0.02)
        }
    }
}
