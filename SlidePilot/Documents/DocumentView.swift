import SlidePilotRendering
import SwiftUI

/// Content of a document window: the current slide and the next-slide preview.
/// The presenter layout replaces this with #13.
struct DocumentView: View {
    @State private var cache: RenderCache
    @State private var page: Int
    @FocusState private var hasKeyboardFocus: Bool

    init(document: PDFFileDocument, page: Int = 0) {
        // Cheap to create: the cache opens the PDF on its first render.
        _cache = State(initialValue: RenderCache(data: document.data, info: document.info))
        _page = State(initialValue: page)
    }

    var body: some View {
        CurrentAndNextSlides(cache: cache, page: $page)
            .shrinksOnMemoryWarning(cache)
            // Interim slide change with ← and → until the navigation commands (#17, NAV-01).
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear { hasKeyboardFocus = true }
            .onKeyPress(.leftArrow) {
                page = max(0, page - 1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                page = min(cache.info.pageCount - 1, page + 1)
                return .handled
            }
    }
}
