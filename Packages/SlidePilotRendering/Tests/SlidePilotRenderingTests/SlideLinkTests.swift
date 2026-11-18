import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import SlidePilotRendering

@Suite struct SlideLinkTests {
    /// What a test puts on a page: an area in page space and where it leads.
    enum Annotation {
        case goTo(CGRect, page: Int)
        case url(CGRect, String)
        case text(CGRect)
    }

    /// A PDF of `pages` pages whose first page carries `annotations`.
    ///
    /// Links are written by Core Graphics with named destinations, like hyperref does.
    /// (Internal links that PDFKit itself writes lose their target page when saved.) Text
    /// annotations and the rotation are added by PDFKit afterwards.
    static func linkedPDF(pages: Int = 3, rotation: Int = 0, _ annotations: [Annotation]) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.addDestination("page\(index)" as CFString, at: .zero)
            if index == 0 {
                for annotation in annotations {
                    switch annotation {
                    case let .goTo(bounds, target):
                        context.setDestination("page\(target)" as CFString, for: bounds)
                    case let .url(bounds, string):
                        context.setURL(try #require(URL(string: string)) as CFURL, for: bounds)
                    case .text:
                        break
                    }
                }
            }
            context.endPDFPage()
        }
        context.closePDF()

        let texts = annotations.compactMap { if case let .text(bounds) = $0 { bounds } else { nil } }
        guard rotation != 0 || !texts.isEmpty else { return data as Data }
        let document = try #require(PDFDocument(data: data as Data))
        let page = try #require(document.page(at: 0))
        for bounds in texts {
            page.addAnnotation(PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil))
        }
        page.rotation = rotation
        return try #require(document.dataRepresentation())
    }

    static func cache(_ data: Data) throws -> RenderCache {
        RenderCache(data: data, info: try PDFInspector.inspect(data))
    }

    static let size = TestPDF.pageSize

    @Test func readsInternalLinksAsPageTargets() async throws {
        let data = try Self.linkedPDF([.goTo(CGRect(x: 10, y: 20, width: 100, height: 30), page: 2)])
        let links = try await Self.cache(data).links(page: 0)
        #expect(links.map(\.target) == [.page(2)])
    }

    @Test func readsURLLinks() async throws {
        let data = try Self.linkedPDF([
            .url(CGRect(x: 10, y: 20, width: 100, height: 30), "https://example.com"),
            .url(CGRect(x: 10, y: 60, width: 100, height: 30), "mailto:someone@example.com"),
        ])
        let links = try await Self.cache(data).links(page: 0)
        #expect(links.map(\.target) == [
            .url(URL(string: "https://example.com")!),
            .url(URL(string: "mailto:someone@example.com")!),
        ])
    }

    @Test func skipsAnnotationsThatAreNotLinks() async throws {
        let data = try Self.linkedPDF([
            .text(CGRect(x: 10, y: 20, width: 20, height: 20)),
            .url(CGRect(x: 10, y: 60, width: 100, height: 30), "https://example.com"),
        ])
        let links = try await Self.cache(data).links(page: 0)
        #expect(links.map(\.target) == [.url(URL(string: "https://example.com")!)])
    }

    @Test func readingLinksAgainGivesTheSameLinks() async throws {
        let data = try Self.linkedPDF([.goTo(CGRect(x: 10, y: 20, width: 100, height: 30), page: 1)])
        let cache = try Self.cache(data)
        // Asked twice: the second answer comes from the cache's memo.
        #expect(await cache.links(page: 0).count == 1)
        #expect(await cache.links(page: 0).count == 1)
    }

    @Test func pagesWithoutLinksAndMissingPagesHaveNone() async throws {
        let data = try Self.linkedPDF([.goTo(CGRect(x: 10, y: 20, width: 100, height: 30), page: 1)])
        let cache = try Self.cache(data)
        #expect(await cache.links(page: 1).isEmpty)
        #expect(await cache.links(page: 99).isEmpty)
    }

    @Test func linkAreaIsAFractionOfThePageWithTheOriginTopLeft() async throws {
        let size = Self.size
        // Bottom left quarter of the page in PDF space (origin bottom left).
        let bounds = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2)
        let data = try Self.linkedPDF([.goTo(bounds, page: 1)])
        let link = try #require(try await Self.cache(data).links(page: 0).first)
        expectClose(link.unitRect, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test(arguments: [
        // The unrotated bottom left quarter turns with the page.
        (90, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        (180, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        (270, CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
    ])
    func linkAreaFollowsThePageRotation(rotation: Int, expected: CGRect) async throws {
        let size = Self.size
        let bounds = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2)
        let data = try Self.linkedPDF(rotation: rotation, [.url(bounds, "https://example.com")])
        let link = try #require(try await Self.cache(data).links(page: 0).first)
        expectClose(link.unitRect, expected)
    }

    @Test func mapsNarrowRectsOnRotatedPages() {
        // A wide, flat link in the top right corner of an unrotated 200×100 page.
        let mediaBox = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bounds = CGRect(x: 150, y: 90, width: 50, height: 10)
        expectClose(
            LinkExtractor.displayedUnitRect(of: bounds, mediaBox: mediaBox, rotation: 0),
            CGRect(x: 0.75, y: 0, width: 0.25, height: 0.1)
        )
        // Turned clockwise, the top right corner becomes the bottom right corner.
        expectClose(
            LinkExtractor.displayedUnitRect(of: bounds, mediaBox: mediaBox, rotation: 90),
            CGRect(x: 0.9, y: 0.75, width: 0.1, height: 0.25)
        )
    }

    @Test func respectsAMediaBoxThatDoesNotStartAtZero() {
        let mediaBox = CGRect(x: 100, y: 50, width: 200, height: 100)
        let bounds = CGRect(x: 100, y: 50, width: 100, height: 50)
        expectClose(
            LinkExtractor.displayedUnitRect(of: bounds, mediaBox: mediaBox, rotation: 0),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        )
    }

    // MARK: - Regions

    // The old app mapped clicks on a half page to the whole page, so links on split-notes
    // slides were hit in the wrong place. Links are measured in the shown region here.
    @Test func linkAreaIsRelativeToTheShownRegion() {
        let link = SlideLink(unitRect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1), target: .page(1))
        expectClose(link.unitRect(in: .full), CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1))
        expectClose(link.unitRect(in: .leftHalf), CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.1))
        expectClose(link.unitRect(in: .topHalf), CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.2))
        #expect(link.unitRect(in: .rightHalf) == nil)
        #expect(link.unitRect(in: .bottomHalf) == nil)
    }

    @Test func linkAcrossTheRegionEdgeIsClipped() {
        let link = SlideLink(unitRect: CGRect(x: 0.4, y: 0, width: 0.2, height: 0.1), target: .page(1))
        expectClose(link.unitRect(in: .rightHalf), CGRect(x: 0, y: 0, width: 0.2, height: 0.1))
    }

    private func expectClose(_ actual: CGRect?, _ expected: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else {
            Issue.record("No rect", sourceLocation: sourceLocation)
            return
        }
        let tolerance = 0.001
        let close = abs(actual.minX - expected.minX) < tolerance
            && abs(actual.minY - expected.minY) < tolerance
            && abs(actual.width - expected.width) < tolerance
            && abs(actual.height - expected.height) < tolerance
        #expect(close, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
    }
}
