import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering

/// State of one open document: the slides and the current page.
/// Later issues add layout, notes, drawing, pointer, curtain and timer state.
@Observable
final class PresentationSession {
    /// Replaced when the PDF is reloaded; views read page sizes from `cache.info`.
    private(set) var cache: RenderCache
    private(set) var position: DeckPosition
    /// The bytes on screen; the file observer compares changes with them.
    @ObservationIgnored private(set) var data: Data

    init(data: Data, info: PDFDocumentInfo, page: Int = 0) {
        self.data = data
        // Cheap to create: the cache opens the PDF on its first render.
        cache = RenderCache(data: data, info: info)
        position = DeckPosition(page: page, pageCount: info.pageCount)
    }

    var currentPage: Int { position.page }

    func showNextPage() {
        position.showNext()
    }

    func showPreviousPage() {
        position.showPrevious()
    }

    /// Shows a recompiled version of the PDF (DOC-08). The page stays, clamped to the
    /// new last page when the deck got shorter (DEF-18).
    func reload(with version: PDFVersion) {
        data = version.data
        cache = RenderCache(data: version.data, info: version.info)
        position.changePageCount(to: version.info.pageCount)
    }
}
