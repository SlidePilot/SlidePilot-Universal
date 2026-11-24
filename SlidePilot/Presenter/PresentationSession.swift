import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering

/// State of one open document: the slides and the current page. The presenter and the
/// presentation observe the same session (DOC-04).
@Observable
final class PresentationSession: Identifiable {
    /// Identifies the session's presentation window (macOS) and its registry entry.
    let id = UUID()
    /// The document's display name, e.g. for the remote's list of presentations (REM-04).
    let title: String
    /// Where the PDF is, if the document system says; a `.slidepilot` file lists the open
    /// PDFs by it (NOTES-11).
    var fileURL: URL?
    /// A `.slidepilot` file opened on its own and handed to this document; its window asks
    /// before importing it (NOTES-11).
    var slidePilotFileRequest: SlidePilotFileRequest?
    /// Replaced when the PDF is reloaded; views read page sizes from `cache.info`.
    private(set) var cache: RenderCache
    /// Temporary files of the videos stored inside the PDF, shared by the caches of all
    /// versions of the PDF; removed when the document closes (#142).
    @ObservationIgnored private let embeddedFiles = EmbeddedFileStore()
    private(set) var position: DeckPosition
    /// Stopwatch/timer of this document; starts in stopwatch mode (TIME-02 to TIME-05).
    var timer = PresentationTimer()
    /// Counts reloads, so the remote knows the slide images changed (REM-04).
    private(set) var contentVersion = 0
    /// Where a remote controller points on the slide, 0…1 with the origin top left; `nil`
    /// when it does not point (REM-05). The pointer overlay (PTR-01) shows it only while
    /// the pointer is shown (DEF-14).
    var remotePointerLocation: CGPoint?
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
    /// Draw mode and the drawings of all pages (DRAW-01 to DRAW-08).
    let drawing = DrawingModel()
    /// Whether the pointer is shown, its appearance and where the presenter points (PTR-01, PTR-02).
    let pointer = PointerState()

    /// Text or split notes and the split position (NOTES-01 to NOTES-03). Starts from the
    /// PDF's keywords; stored per-document settings replace it once loaded (SET-02).
    private(set) var notesDisplay: NotesDisplay {
        didSet {
            // The remote's slide images show other halves now (REM-04).
            if notesDisplay != oldValue { contentVersion += 1 }
        }
    }

    init(
        data: Data,
        title: String = String(localized: "Untitled"),
        info: PDFDocumentInfo,
        page: Int = 0,
        layoutStore: any PresenterLayoutStore = UserDefaultsPresenterLayoutStore.app,
        companionStore: CompanionStore? = .app,
        folderAccessStore: FolderAccessStore? = nil
    ) {
        self.data = data
        self.title = title
        linkedFiles = LinkedFiles(folderStore: folderAccessStore)
        layout = PresenterLayoutModel(store: layoutStore)
        companion = DocumentCompanion(store: companionStore)
        notes = NotesModel(companion: companion)
        // Cheap to create: the cache opens the PDF on its first render.
        cache = RenderCache(data: data, info: info, embeddedFiles: embeddedFiles)
        position = DeckPosition(page: page, pageCount: info.pageCount)
        notesDisplay = NotesDisplay(pdfKeywords: info.keywords)
    }

    var currentPage: Int { position.page }

    /// Every slide change goes through the methods below; none of them changes the slide
    /// while draw mode blocks it (NAV-04), also for links, swipes and the remote.
    var allowsPageSwitching: Bool { drawing.drawings.allowsPageSwitching }

    func showNextPage() {
        guard allowsPageSwitching else { return }
        position.showNext()
    }

    func showPreviousPage() {
        guard allowsPageSwitching else { return }
        position.showPrevious()
    }

    /// Jumps to `index`, clamped to the deck (navigator LAY-06, internal links NAV-05).
    /// Counts for Go Back; never starts the timer.
    func showPage(_ index: Int) {
        guard allowsPageSwitching else { return }
        position.show(index)
    }

    var canGoBack: Bool { allowsPageSwitching && position.canGoBack }

    /// Shows the previously viewed page (NAV-03).
    func goBack() {
        guard allowsPageSwitching else { return }
        position.goBack()
    }

    /// The part of each page the audience sees: current and next slide, presentation,
    /// thumbnails, drawings and the remote (NOTES-02).
    var audienceRegion: PageRegion { .audience(notesDisplay.position) }

    /// The notes half shown in the notes slot, or `nil` for text notes (NOTES-01, NOTES-02).
    var splitNotesRegion: PageRegion? {
        notesDisplay.showsSplitNotes ? .notes(notesDisplay.position) : nil
    }

    private var areNotesShown: Bool { layout.isVisible(.notes) }

    /// Notes ▸ Notes Mode (NOTES-01).
    func setNotesMode(_ mode: NotesMode) {
        notesDisplay.setMode(mode, notesShown: areNotesShown)
        if notesDisplay.showsSplitNotes { notes.finishEditing() }
    }

    /// Notes ▸ Split Position (NOTES-02).
    func setNotesPosition(_ position: NotesPosition) {
        notesDisplay.setPosition(position, notesShown: areNotesShown)
        if notesDisplay.showsSplitNotes { notes.finishEditing() }
    }

    /// Call when the notes slot appears (NOTES-02).
    func notesSlotDidShow() {
        notesDisplay.notesDidShow()
    }

    /// Applies stored per-document settings (SET-02); they win over the keywords. Position
    /// first, then mode, coupled like the old app's `load(configuration:)`.
    func applyStoredNotesDisplay(mode: NotesMode?, position: NotesPosition?) {
        notesDisplay.applyStored(mode: mode, position: position, notesShown: areNotesShown)
        if notesDisplay.showsSplitNotes { notes.finishEditing() }
    }

    /// Removes the copies of embedded videos right away when the window closes (#142);
    /// the session itself may be released later.
    func documentClosed() {
        let embeddedFiles = embeddedFiles
        Task { await embeddedFiles.removeAll() }
    }

    /// Shows a recompiled version of the PDF (DOC-08). The page stays, clamped to the
    /// new last page when the deck got shorter (DEF-18).
    func reload(with version: PDFVersion) {
        data = version.data
        cache = RenderCache(data: version.data, info: version.info, embeddedFiles: embeddedFiles)
        contentVersion += 1
        position.changePageCount(to: version.info.pageCount)
        drawing.drawings.pageCountChanged(to: version.info.pageCount)
    }
}
