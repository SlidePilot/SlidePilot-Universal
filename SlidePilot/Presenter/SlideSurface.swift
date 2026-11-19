import SlidePilotCore
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
        /// The audience's slide on the presentation window or external display.
        case presentation
    }

    let cache: RenderCache
    let page: Int
    var region: PageRegion = .full
    var role: Role = .current
    /// Follows internal links (NAV-05); `nil` turns all links off, also URL links.
    var pageLinkAction: ((Int) -> Void)?
    /// Fades a new slide in over the previous one (LAY-07); only for the presentation.
    var crossfades = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.openURL) private var openURL
    @State private var slide: RenderedSlide?
    @State private var box: PixelSize?
    @State private var pageLinks: PageLinks?
    @State private var pageMovies: PageMovies?
    @Environment(LinkedFiles.self) private var linkedFiles: LinkedFiles?
    /// Counts crossfaded slide changes, so the new slide is a new view on top of the old one.
    @State private var generation = 0
    /// The cache the shown image came from; a reloaded PDF fades in too, like the old app.
    @State private var slideCache: ObjectIdentifier?

    private struct LinkRequest: Equatable {
        let cache: ObjectIdentifier
        let page: Int
    }

    /// The links of one page of one cache, so a page change never shows stale links.
    private struct PageLinks {
        let cache: ObjectIdentifier
        let page: Int
        let links: [SlideLink]
    }

    /// The videos of one page of one cache (NAV-07).
    private struct PageMovies {
        let cache: ObjectIdentifier
        let page: Int
        let movies: [SlideMovie]
    }

    private struct Request: Equatable {
        /// A reloaded PDF comes with a new cache (DOC-08); the old image stays until the
        /// new one is rendered.
        let cache: ObjectIdentifier
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
                ZStack {
                    if let slide {
                        Image(decorative: slide.image, scale: scale)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .id(generation)
                            .zIndex(Double(generation))
                            // The new slide fades in; the old one stays opaque below it
                            // until the fade ends, like the old app's layer transition.
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.animation(.linear(duration: 0).delay(SlideCrossfade.duration))
                            ))
                    }
                }
            }
            .overlay {
                SlideLinkLayer(links: links, region: region, follow: follow)
            }
            .onGeometryChange(for: PixelSize.self) { proxy in
                PixelSize(
                    width: Int((proxy.size.width * scale).rounded(.up)),
                    height: Int((proxy.size.height * scale).rounded(.up))
                )
            } action: { newBox in
                box = newBox
            }
            .task(id: Request(cache: ObjectIdentifier(cache), page: page, region: region, box: box)) {
                await load()
            }
            .task(id: LinkRequest(cache: ObjectIdentifier(cache), page: page)) {
                await loadLinks()
            }
            .task(id: LinkRequest(cache: ObjectIdentifier(cache), page: page)) {
                await loadMovies()
            }
            // The presentation shows the slide on black without a frame.
            .slideOutline(role != .presentation)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityActions {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button { follow(link) } label: { link.accessibilityActionName }
                }
            }
            // After the slide's own accessibility element, so VoiceOver reaches the players.
            .overlay {
                SlideMovieLayer(movies: movies, region: region, page: page, isPresenter: role == .current)
            }
    }

    /// The links of the shown page and region, empty while links are off.
    private var links: [SlideLink] {
        guard pageLinkAction != nil, let pageLinks,
              pageLinks.cache == ObjectIdentifier(cache), pageLinks.page == page
        else { return [] }
        return pageLinks.links.filter { $0.unitRect(in: region) != nil }
    }

    /// The videos of the shown page. The next-slide preview shows only the PDF's poster.
    private var movies: [SlideMovie] {
        guard role != .next, let pageMovies,
              pageMovies.cache == ObjectIdentifier(cache), pageMovies.page == page
        else { return [] }
        return pageMovies.movies
    }

    private func follow(_ link: SlideLink) {
        switch link.target {
        case .page(let index): pageLinkAction?(index)
        case .url(let url): openURL(url)
        case .file(let reference): linkedFiles?.open(reference)
        }
    }

    private func loadMovies() async {
        guard role != .next, linkedFiles != nil else { return }
        let movies = await cache.movies(page: page)
        guard !Task.isCancelled else { return }
        pageMovies = PageMovies(cache: ObjectIdentifier(cache), page: page, movies: movies)
    }

    private func loadLinks() async {
        guard pageLinkAction != nil else { return }
        let links = await cache.links(page: page)
        guard !Task.isCancelled else { return }
        pageLinks = PageLinks(cache: ObjectIdentifier(cache), page: page, links: links)
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
        case .presentation: Text("Presentation, slide \(number) of \(count)")
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
        let renderedCache = ObjectIdentifier(cache)
        let isNewSlide = slide.map {
            $0.pageIndex != rendered.pageIndex || $0.region != rendered.region || slideCache != renderedCache
        } ?? false
        slideCache = renderedCache
        guard crossfades, isNewSlide else {
            // The same view shows the new image at once: no transition runs.
            slide = rendered
            return
        }
        withAnimation(.easeInOut(duration: SlideCrossfade.duration)) {
            generation += 1
            slide = rendered
        }
    }
}

extension View {
    /// A hairline around a slide, so white pages stand out from a light window background
    /// and black pages from a dark one.
    func slideOutline(_ isShown: Bool = true) -> some View {
        overlay {
            if isShown {
                Rectangle().strokeBorder(.separator, lineWidth: 1)
            }
        }
    }
}
