import PDFKit
import SwiftUI

// PROTOTYPE (issue #7). Renders on the main actor; the real render cache is issue #8.

/// Draws one PDF page aspect-fit into the available space, at the pixel size of the
/// display the view is on, so the projector shows a sharp image.
struct SlideImageView: View {
    let session: PrototypeSession
    let pageIndex: Int
    /// Log render size and time (only for the presentation surface).
    var logsRendering = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)
            ZStack {
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .overlay {
                            if !logsRendering { Rectangle().strokeBorder(.separator) }
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: RenderKey(generation: session.documentGeneration, page: pageIndex, size: fitted, scale: displayScale)) {
                render(size: fitted)
            }
        }
    }

    private struct RenderKey: Equatable {
        let generation: Int
        let page: Int
        let size: CGSize
        let scale: CGFloat
    }

    private func pageSize() -> CGSize? {
        guard let page = session.page(at: pageIndex) else { return nil }
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        guard let pageSize = pageSize(), pageSize.width > 0, pageSize.height > 0,
              available.width > 0, available.height > 0
        else { return .zero }
        let scale = min(available.width / pageSize.width, available.height / pageSize.height)
        return CGSize(width: (pageSize.width * scale).rounded(.down), height: (pageSize.height * scale).rounded(.down))
    }

    private func render(size: CGSize) {
        guard let page = session.page(at: pageIndex), let pageSize = pageSize(), size.width >= 1, size.height >= 1 else {
            image = nil
            return
        }
        let pixelWidth = Int((size.width * displayScale).rounded())
        let pixelHeight = Int((size.height * displayScale).rounded())
        let clock = ContinuousClock()
        let started = clock.now
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(pixelWidth) / pageSize.width, y: CGFloat(pixelHeight) / pageSize.height)
        // PDFPage.draw applies the page rotation and crop box origin itself.
        page.draw(with: .cropBox, to: context)
        image = context.makeImage()
        if logsRendering {
            let ms = (clock.now - started) / .milliseconds(1)
            session.record(
                "presentation rendered page \(pageIndex + 1): \(pixelWidth)×\(pixelHeight) px "
                    + "(\(Int(size.width))×\(Int(size.height)) pt @\(displayScale.formatted())x) in \(String(format: "%.1f", ms)) ms"
            )
        }
    }
}
