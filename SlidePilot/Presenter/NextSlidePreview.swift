import SlidePilotRendering
import SwiftUI

/// The slide after `currentPage`, or the end-of-deck page after the last slide (LAY-09).
struct NextSlidePreview: View {
    let cache: RenderCache
    let currentPage: Int
    var region: PageRegion = .full

    var body: some View {
        let next = currentPage + 1
        if next < cache.info.pageCount {
            SlideSurface(cache: cache, page: next, region: region, role: .next)
        } else {
            EndOfDeckView(aspectRatio: lastPageSize)
        }
    }

    private var lastPageSize: CGSize {
        guard let size = cache.info.pageSizes.last else { return CGSize(width: 4, height: 3) }
        return region.size(onPageOfSize: size)
    }
}

/// A black page with a short note, shown in place of the next slide after the last one.
///
/// Part of the slide surface: the old app showed a plain black page here. The note tells
/// it apart from a black slide in the deck (approved deviation, LAY-09).
struct EndOfDeckView: View {
    let aspectRatio: CGSize

    var body: some View {
        Color.black
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                Text("End of presentation")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding()
                    // The page is black in light and dark mode, so the text always uses the dark style.
                    .environment(\.colorScheme, .dark)
            }
            .slideOutline()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Next slide: end of presentation"))
    }
}
