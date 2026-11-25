import Foundation
import Testing
@testable import SlidePilotRendering

/// Release check (#41): a whole presentation through the 320-page fixture stays within the
/// cache budget and keeps each step fast. Results are in `docs/performance.md`.
@Suite(.serialized) struct LongPresentationTests {
    /// 4K audience size: 2880×2160 per 4:3 page, about 23.7 MiB per image.
    private static let audience = PixelSize(width: 3840, height: 2160)
    private static let thumbnail = PixelSize(width: 400, height: 300)

    private func fixtureData(_ name: String, filePath: String = #filePath) throws -> Data {
        let root = URL(filePath: filePath)
            .deletingLastPathComponent() // SlidePilotRenderingTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SlidePilotRendering
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository
        return try Data(contentsOf: root.appending(path: "Fixtures/\(name)"))
    }

    /// The iPad budget is the tighter one, so the check uses it on both platforms.
    private func makeCache() throws -> RenderCache {
        let data = try fixtureData("large-deck.pdf")
        let info = try PDFInspector.inspect(data)
        let configuration = RenderCache.Configuration(
            budgetBytes: 192 << 20, thumbnailBudgetBytes: 16 << 20, backgroundWorkers: 2
        )
        return RenderCache(data: data, info: info, configuration: configuration)
    }

    /// One step of the presenter: focus on the page, then wait for its image.
    private func show(_ page: Int, in cache: RenderCache) async throws -> Duration {
        let clock = ContinuousClock()
        return try await clock.measure {
            await cache.focus(on: page, region: .full, fitting: Self.audience)
            let slide = try await cache.image(page: page, region: .full, fitting: Self.audience)
            #expect(slide.pageIndex == page)
        }
    }

    private func percentile(_ values: [Duration], _ fraction: Double) -> Duration {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    @Test(.timeLimit(.minutes(5)))
    func forwardAndBackThroughTheWholeDeckStaysWithinBudget() async throws {
        let cache = try makeCache()
        #expect(cache.info.pageCount == 320)
        var steps: [Duration] = []
        var peakBytes = 0
        let pages = Array(0..<320) + Array((0..<319).reversed())
        for page in pages {
            steps.append(try await show(page, in: cache))
            let used = await cache.usedBytes
            peakBytes = max(peakBytes, used)
            #expect(used <= 192 << 20)
        }
        // Jumps like the overview or Go to Page: render on demand, no neighborhood yet.
        for page in [300, 12, 250, 87, 319, 0, 160] {
            steps.append(try await show(page, in: cache))
        }
        // The sidebar scrolls through every thumbnail; its store has its own budget.
        for page in 0..<320 {
            _ = try await cache.thumbnail(page: page, region: .full, fitting: Self.thumbnail)
            #expect(await cache.thumbnailBytes <= 16 << 20)
        }

        let median = percentile(steps, 0.5)
        let p95 = percentile(steps, 0.95)
        print("LONGPRESENTATION steps=\(steps.count) median=\(median) p95=\(p95) max=\(steps.max()!) peakMiB=\(peakBytes >> 20)")
        // Generous limit so slow CI runners do not flake; real numbers are in the doc.
        #expect(p95 < .milliseconds(500))
    }
}
