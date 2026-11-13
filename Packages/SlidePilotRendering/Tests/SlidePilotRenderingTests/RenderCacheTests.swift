import CoreGraphics
import Foundation
import Testing
@testable import SlidePilotRendering

@Suite struct PageGeometryTests {
    @Test(arguments: [(0, false), (90, true), (180, false), (270, true), (360, false), (-90, true)])
    func displayedSizeSwapsSidesForQuarterTurns(rotation: Int, swapped: Bool) {
        let mediaBox = CGRect(x: 10, y: 20, width: 400, height: 300)
        let size = PageGeometry.displayedSize(mediaBox: mediaBox, rotation: rotation)
        #expect(size == (swapped ? CGSize(width: 300, height: 400) : CGSize(width: 400, height: 300)))
    }

    @Test func regionRectsUseCoreGraphicsOrigin() {
        let size = CGSize(width: 400, height: 300)
        #expect(PageGeometry.regionRect(.topHalf, displayedSize: size) == CGRect(x: 0, y: 150, width: 400, height: 150))
        #expect(PageGeometry.regionRect(.bottomHalf, displayedSize: size) == CGRect(x: 0, y: 0, width: 400, height: 150))
        #expect(PageGeometry.regionRect(.rightHalf, displayedSize: size) == CGRect(x: 200, y: 0, width: 200, height: 300))
    }

    @Test func aspectFitKeepsTheContentRatio() {
        let box = PixelSize(width: 1920, height: 1080)
        #expect(box.aspectFit(CGSize(width: 4, height: 3)) == PixelSize(width: 1440, height: 1080))
        #expect(box.aspectFit(CGSize(width: 32, height: 9)) == PixelSize(width: 1920, height: 540))
        #expect(PixelSize(width: 0, height: 10).aspectFit(CGSize(width: 4, height: 3)) == PixelSize(width: 1, height: 1))
    }

    @Test func halvesAreHalfThePage() {
        let page = CGSize(width: 800, height: 300)
        #expect(PageRegion.leftHalf.size(onPageOfSize: page) == CGSize(width: 400, height: 300))
        #expect(PageRegion.topHalf.size(onPageOfSize: page) == CGSize(width: 800, height: 150))
        #expect(PageRegion.full.size(onPageOfSize: page) == page)
    }
}

@Suite struct RenderCacheTests {
    private static let box = PixelSize(width: 400, height: 300)

    private func makeCache(
        pages: Int,
        data: Data? = nil,
        budget: Int = 512 << 20,
        thumbnailBudget: Int = 32 << 20
    ) throws -> RenderCache {
        let data = data ?? TestPDF.make(pages: pages)
        let info = try PDFInspector.inspect(data)
        let configuration = RenderCache.Configuration(
            budgetBytes: budget, thumbnailBudgetBytes: thumbnailBudget, backgroundWorkers: 2
        )
        return RenderCache(data: data, info: info, configuration: configuration)
    }

    @Test func rendersAPageAspectFittedIntoTheBox() async throws {
        let cache = try makeCache(pages: 2)
        let slide = try await cache.image(page: 0, region: .full, fitting: PixelSize(width: 1920, height: 1080))
        #expect(slide.pixelSize == PixelSize(width: 1440, height: 1080))
        #expect(PixelProbe.color(of: slide.image, atUnit: CGPoint(x: 0.25, y: 0.5)) == .red)
        #expect(PixelProbe.color(of: slide.image, atUnit: CGPoint(x: 0.75, y: 0.5)) == .blue)
    }

    @Test func rendersOnlyTheRequestedHalf() async throws {
        let cache = try makeCache(pages: 1)
        let left = try await cache.image(page: 0, region: .leftHalf, fitting: Self.box)
        let right = try await cache.image(page: 0, region: .rightHalf, fitting: Self.box)
        #expect(PixelProbe.color(of: left.image, atUnit: CGPoint(x: 0.1, y: 0.5)) == .red)
        #expect(PixelProbe.color(of: left.image, atUnit: CGPoint(x: 0.9, y: 0.5)) == .red)
        #expect(PixelProbe.color(of: right.image, atUnit: CGPoint(x: 0.1, y: 0.5)) == .blue)
        #expect(PixelProbe.color(of: right.image, atUnit: CGPoint(x: 0.9, y: 0.5)) == .blue)
    }

    /// Halves are taken in the displayed orientation. Rotating a page 90° clockwise moves
    /// its left (red) half to the top, so the displayed top half must be red.
    @Test(arguments: [(90, PixelProbe.Color.red, PixelProbe.Color.blue),
                      (180, .blue, .red),
                      (270, .blue, .red)])
    func rotatedPagesAreShownInTheirDisplayedOrientation(
        rotation: Int, topOrLeft: PixelProbe.Color, bottomOrRight: PixelProbe.Color
    ) async throws {
        let data = try TestPDF.rotating(TestPDF.make(pages: 1), by: [rotation])
        let cache = try makeCache(pages: 1, data: data)
        let full = try await cache.image(page: 0, region: .full, fitting: PixelSize(width: 1000, height: 1000))
        if rotation == 180 {
            #expect(full.pixelSize.width > full.pixelSize.height)
            #expect(PixelProbe.color(of: full.image, atUnit: CGPoint(x: 0.25, y: 0.5)) == topOrLeft)
            #expect(PixelProbe.color(of: full.image, atUnit: CGPoint(x: 0.75, y: 0.5)) == bottomOrRight)
            let left = try await cache.image(page: 0, region: .leftHalf, fitting: Self.box)
            let right = try await cache.image(page: 0, region: .rightHalf, fitting: Self.box)
            #expect(PixelProbe.color(of: left.image, atUnit: CGPoint(x: 0.5, y: 0.5)) == topOrLeft)
            #expect(PixelProbe.color(of: right.image, atUnit: CGPoint(x: 0.5, y: 0.5)) == bottomOrRight)
        } else {
            #expect(full.pixelSize.width < full.pixelSize.height)
            let top = try await cache.image(page: 0, region: .topHalf, fitting: Self.box)
            let bottom = try await cache.image(page: 0, region: .bottomHalf, fitting: Self.box)
            #expect(PixelProbe.color(of: top.image, atUnit: CGPoint(x: 0.5, y: 0.5)) == topOrLeft)
            #expect(PixelProbe.color(of: bottom.image, atUnit: CGPoint(x: 0.5, y: 0.5)) == bottomOrRight)
        }
    }

    /// DEF-02: the old cache changed the shared page's crop box while rendering.
    @Test func renderingNeverChangesThePDF() async throws {
        let data = TestPDF.make(pages: 1)
        let cache = try makeCache(pages: 1, data: data)
        _ = try await cache.image(page: 0, region: .rightHalf, fitting: Self.box)
        let info = try PDFInspector.inspect(data)
        #expect(info.pageSizes == [TestPDF.pageSize])
    }

    @Test func smallerRequestsReuseTheLargerImage() async throws {
        let cache = try makeCache(pages: 2)
        let large = try await cache.image(page: 1, region: .full, fitting: PixelSize(width: 1600, height: 1200))
        let small = try await cache.image(page: 1, region: .full, fitting: PixelSize(width: 400, height: 300))
        #expect(small.image === large.image)
        #expect(await cache.cachedKeys.count == 1)
    }

    @Test func largerRequestsReplaceTheSmallerImage() async throws {
        let cache = try makeCache(pages: 1)
        let small = try await cache.image(page: 0, region: .full, fitting: Self.box)
        let large = try await cache.image(page: 0, region: .full, fitting: PixelSize(width: 1600, height: 1200))
        #expect(large.pixelSize.covers(small.pixelSize) && large.pixelSize != small.pixelSize)
        #expect(await cache.usedBytes == large.byteCount)
    }

    @Test func unknownPagesThrow() async throws {
        let cache = try makeCache(pages: 2)
        await #expect(throws: RenderError.pageNotFound) {
            try await cache.image(page: 2, region: .full, fitting: Self.box)
        }
        await #expect(throws: RenderError.pageNotFound) {
            try await cache.image(page: -1, region: .full, fitting: Self.box)
        }
    }

    @Test func focusRendersTheNeighborhood() async throws {
        let cache = try makeCache(pages: 10)
        await cache.focus(on: 4, region: .full, fitting: Self.box)
        let current = try await cache.image(page: 4, region: .full, fitting: Self.box)
        #expect(current.pageIndex == 4)
        // Wait for the background jobs of pages 3, 5, 6 and 7.
        for page in [3, 5, 6, 7] {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }
        let pages = Set(await cache.cachedKeys.map(\.page))
        #expect(pages == [3, 4, 5, 6, 7])
    }

    @Test func budgetEvictsOldPagesButKeepsCurrentAndNext() async throws {
        // Room for about three images of 400×300 (480 000 bytes each).
        let cache = try makeCache(pages: 20, budget: 1_500_000)
        for page in 0..<8 {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }
        await cache.focus(on: 10, region: .full, fitting: Self.box)
        // Wait for the whole neighborhood, which alone exceeds the budget.
        for page in [10, 11, 9, 12, 13] {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }

        #expect(await cache.usedBytes <= 1_500_000)
        let pages = Set(await cache.cachedKeys.map(\.page))
        #expect(pages.isSuperset(of: [10, 11]))
        #expect(pages.isDisjoint(with: 0..<8))
    }

    @Test func budgetSmallerThanTwoImagesStillKeepsCurrentAndNext() async throws {
        let cache = try makeCache(pages: 4, budget: 100_000)
        await cache.focus(on: 1, region: .full, fitting: Self.box)
        _ = try await cache.image(page: 1, region: .full, fitting: Self.box)
        _ = try await cache.image(page: 2, region: .full, fitting: Self.box)
        let pages = Set(await cache.cachedKeys.map(\.page))
        #expect(pages.isSuperset(of: [1, 2]))
    }

    @Test func shrinkToNeighborhoodDropsEverythingElse() async throws {
        let cache = try makeCache(pages: 20)
        for page in 12..<16 {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }
        await cache.focus(on: 2, region: .full, fitting: Self.box)
        for page in 1...5 {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }
        _ = try await cache.thumbnail(page: 0, region: .full, fitting: PixelSize(width: 100, height: 75))
        await cache.shrinkToNeighborhood()
        #expect(Set(await cache.cachedKeys.map(\.page)) == [1, 2, 3, 4, 5])
        #expect(await cache.thumbnailBytes == 0)
    }

    @Test func navigatingAwayCancelsQueuedNeighborhoodJobs() async throws {
        let cache = try makeCache(pages: 200)
        // Jump through the deck faster than it can render; only the last neighborhood matters.
        for page in stride(from: 0, to: 200, by: 10) {
            await cache.focus(on: page, region: .full, fitting: Self.box)
        }
        _ = try await cache.image(page: 190, region: .full, fitting: Self.box)
        for page in [189, 191, 192, 193] {
            _ = try await cache.image(page: page, region: .full, fitting: Self.box)
        }
        let pages = Set(await cache.cachedKeys.map(\.page))
        #expect(pages.isSuperset(of: 189...193))
    }

    /// Jobs cancelled while queued must not block the page when the presenter comes back.
    @Test(.timeLimit(.minutes(1)))
    func returningToAPageWithACancelledJobRendersIt() async throws {
        let cache = try makeCache(pages: 200)
        for _ in 0..<5 {
            await cache.focus(on: 1, region: .full, fitting: Self.box)
            await cache.focus(on: 100, region: .full, fitting: Self.box)
            await cache.focus(on: 3, region: .full, fitting: Self.box)
        }
        for page in [1, 2, 3, 4, 5, 6] {
            let slide = try await cache.image(page: page, region: .full, fitting: Self.box)
            #expect(slide.pageIndex == page)
        }
    }

    // PRE-02: thumbnails come from the same cache, in their own store and budget.
    @Test func thumbnailsHaveTheirOwnStore() async throws {
        let cache = try makeCache(pages: 3)
        let thumbnail = try await cache.thumbnail(page: 2, region: .full, fitting: PixelSize(width: 200, height: 150))
        #expect(thumbnail.pixelSize == PixelSize(width: 200, height: 150))
        #expect(PixelProbe.color(of: thumbnail.image, atUnit: CGPoint(x: 0.25, y: 0.5)) == .red)
        #expect(await cache.cachedKeys.isEmpty)
        #expect(await cache.thumbnailBytes == thumbnail.byteCount)
        let again = try await cache.thumbnail(page: 2, region: .full, fitting: PixelSize(width: 200, height: 150))
        #expect(again.image === thumbnail.image)
    }

    @Test func thumbnailBudgetEvictsLeastRecentlyUsed() async throws {
        // 200×150 thumbnails are 120 000 bytes; room for two.
        let cache = try makeCache(pages: 5, thumbnailBudget: 250_000)
        for page in 0..<5 {
            _ = try await cache.thumbnail(page: page, region: .full, fitting: PixelSize(width: 200, height: 150))
        }
        #expect(await cache.thumbnailBytes <= 250_000)
    }

    // PRE-02: a remote client asks for the same pages at its own size and gets the cached image.
    @Test func concurrentRequestsShareOneRender() async throws {
        let cache = try makeCache(pages: 1)
        async let first = cache.image(page: 0, region: .full, fitting: PixelSize(width: 1600, height: 1200))
        async let second = cache.image(page: 0, region: .full, fitting: PixelSize(width: 1600, height: 1200))
        let (a, b) = try await (first, second)
        #expect(a.image === b.image)
    }
}
