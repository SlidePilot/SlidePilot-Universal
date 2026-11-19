import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SlidePilotRendering

@Suite("Remote slide images (REM-04)")
struct SlideImageEncoderTests {
    @Test func renderedSlideBecomesAJPEGOfTheSameSize() async throws {
        let data = TestPDF.make(pages: 2)
        let cache = RenderCache(data: data, info: try PDFInspector.inspect(data))
        let slide = try await cache.image(page: 1, region: .full, fitting: PixelSize(width: 400, height: 300))

        let jpeg = try SlideImageEncoder.jpeg(slide.image)

        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == slide.image.width)
        #expect(decoded.height == slide.image.height)
    }

    @Test func lowerQualityIsSmaller() async throws {
        let data = TestPDF.make(pages: 1)
        let cache = RenderCache(data: data, info: try PDFInspector.inspect(data))
        let slide = try await cache.image(page: 0, region: .full, fitting: PixelSize(width: 800, height: 600))
        let small = try SlideImageEncoder.jpeg(slide.image, quality: 0.1)
        let large = try SlideImageEncoder.jpeg(slide.image, quality: 1)
        #expect(small.count < large.count)
    }
}
