import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering

/// State of one open document: the slides and the current page. The presenter and the
/// presentation observe the same session (DOC-04).
/// Later issues add layout, notes, drawing, pointer, curtain and timer state.
@Observable
final class PresentationSession: Identifiable {
    /// Identifies the session's presentation window (macOS) and its registry entry.
    let id = UUID()
    /// Replaced when the PDF is reloaded; views read page sizes from `cache.info`.
    private(set) var cache: RenderCache
    private(set) var position: DeckPosition
    /// Stopwatch/timer of this document; starts in stopwatch mode (TIME-02 to TIME-05).
    var timer = PresentationTimer()
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

    var canGoBack: Bool { position.canGoBack }

    /// Shows the previously viewed page (NAV-03).
    func goBack() {
        position.goBack()
    }

    /// Shows a recompiled version of the PDF (DOC-08). The page stays, clamped to the
    /// new last page when the deck got shorter (DEF-18).
    func reload(with version: PDFVersion) {
        data = version.data
        cache = RenderCache(data: version.data, info: version.info)
        position.changePageCount(to: version.info.pageCount)
    }
}
