import SlidePilotRendering
import SwiftUI

/// Shows one page region of the PDF as rendered by the `RenderCache`.
///
/// This is the slide surface, one of the few places where ADR 0010 allows custom drawing.
/// The view keeps the page's aspect ratio and asks the cache for an image at its own pixel
/// size; while a new page renders, the previous image stays visible to avoid flicker.
struct SlideSurface: View {
    enum Role {
        case current
        case next
    }

    let cache: RenderCache
    let page: Int
    var region: PageRegion = .full
    var role: Role = .current

    @Environment(\.displayScale) private var displayScale
    @State private var slide: RenderedSlide?
    @State private var box: PixelSize?

    private struct Request: Equatable {
        let page: Int
        let region: PageRegion
        let box: PixelSize?
    }

    var body: some View {
        let scale = displayScale
        // A blank page until the first render arrives: PDF pages are drawn on white paper.
        Color.white
            .aspectRatio(regionSize, contentMode: .fit)
            .overlay {
                if let slide {
                    Image(decorative: slide.image, scale: scale)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .onGeometryChange(for: PixelSize.self) { proxy in
                PixelSize(
                    width: Int((proxy.size.width * scale).rounded(.up)),
                    height: Int((proxy.size.height * scale).rounded(.up))
                )
            } action: { newBox in
                box = newBox
            }
            .task(id: Request(page: page, region: region, box: box)) {
                await load()
            }
            .slideOutline()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }

    private var regionSize: CGSize {
        let pageSize = cache.info.pageSizes.indices.contains(page) ? cache.info.pageSizes[page] : .zero
        let size = region.size(onPageOfSize: pageSize)
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 4, height: 3)
    }

    private var accessibilityLabel: Text {
        let number = page + 1
        let count = cache.info.pageCount
        return switch role {
        case .current: Text("Current slide, \(number) of \(count)")
        case .next: Text("Next slide, \(number) of \(count)")
        }
    }

    private func load() async {
        guard let box, box.width > 0, box.height > 0 else { return }
        // Live window resizing changes the size many times a second; wait until it settles
        // before rendering the same page again at a new size.
        if slide?.pageIndex == page, slide?.region == region {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        if role == .current {
            await cache.focus(on: page, region: region, fitting: box)
        }
        guard let rendered = try? await cache.image(page: page, region: region, fitting: box),
              !Task.isCancelled
        else { return }
        slide = rendered
    }
}

extension View {
    /// A hairline around a slide, so white pages stand out from a light window background
    /// and black pages from a dark one.
    func slideOutline() -> some View {
        overlay {
            Rectangle().strokeBorder(.separator, lineWidth: 1)
        }
    }
}
