import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering

/// State of one open document: the slides and the current page. The presenter and the
/// presentation observe the same session (DOC-04).
/// Later issues add notes, drawing and pointer state.
@Observable
final class PresentationSession: Identifiable {
    /// Identifies the session's presentation window (macOS) and its registry entry.
    let id = UUID()
    /// Replaced when the PDF is reloaded; views read page sizes from `cache.info`.
    private(set) var cache: RenderCache
    private(set) var position: DeckPosition
    /// Stopwatch/timer of this document; starts in stopwatch mode (TIME-02 to TIME-05).
    var timer = PresentationTimer()
    /// Black or white cover on the presentation (CUR-01); never persisted (CUR-03).
    var curtain = Curtain.none
    /// The bytes on screen; the file observer compares changes with them.
    @ObservationIgnored private(set) var data: Data
    /// The presenter's arrangement and slots (LAY-01 to LAY-05).
    let layout: PresenterLayoutModel
    /// Per-document settings and notes in the companion file (NOTES-10, SET-02).
    let companion: DocumentCompanion
    /// The text notes and whether they are being edited (NOTES-04, NOTES-05).
    let notes: NotesModel
    /// Videos and `run:` link targets next to the PDF (NAV-06, NAV-07).
    let linkedFiles: LinkedFiles
    /// Whether the slide navigator sidebar is shown (LAY-06); hidden when a document opens,
    /// unless the document's settings say otherwise (SET-02).
    var isNavigatorDisplayed = false

    init(
        data: Data,
        info: PDFDocumentInfo,
        page: Int = 0,
        layoutStore: any PresenterLayoutStore = UserDefaultsPresenterLayoutStore.app,
        companionStore: CompanionStore? = .app,
        folderAccessStore: FolderAccessStore? = nil
    ) {
        self.data = data
        linkedFiles = LinkedFiles(folderStore: folderAccessStore)
        layout = PresenterLayoutModel(store: layoutStore)
        companion = DocumentCompanion(store: companionStore)
        notes = NotesModel(companion: companion)
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

    /// Jumps to `index`, clamped to the deck (navigator LAY-06, internal links NAV-05).
    /// Counts for Go Back; never starts the timer.
    func showPage(_ index: Int) {
        position.show(index)
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
