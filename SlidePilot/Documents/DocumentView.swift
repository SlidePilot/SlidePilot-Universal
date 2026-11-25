import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// Content of a document window, the presenter (DOC-04), in the presenter layout (LAY-01).
struct DocumentView: View {
    /// The opened file, watched for recompiles (DOC-08). `nil` when the document system
    /// provides no URL; the PDF is then shown as opened.
    let fileURL: URL?
    @State private var session: PresentationSession
    @Environment(SessionRegistry.self) private var registry

    init(
        document: PDFFileDocument,
        fileURL: URL? = nil,
        page: Int = 0,
        layoutStore: any PresenterLayoutStore = UserDefaultsPresenterLayoutStore.app,
        companionStore: CompanionStore? = .app,
        folderAccessStore: FolderAccessStore? = .app
    ) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(
            data: document.data,
            title: fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled"),
            info: document.info,
            page: page, layoutStore: layoutStore, companionStore: companionStore,
            folderAccessStore: folderAccessStore
        ))
    }

    var body: some View {
        // The navigator sidebar (LAY-06) next to the slides.
        SlideNavigatorSplitView(
            session: session,
            slidesChrome: PresenterClock(session: session),
            chrome: PresenterChrome(session: session)
        ) {
            PresenterLayoutView(session: session)
        }
            // Done and the drawing tools stay in a compact bar (#152).
            .presenterToolbarFocus(session)
            .shrinksOnMemoryWarning(session)
            .companionFile(session, fileURL: fileURL)
            // "Save drawings" and the stored drawings (DRAW-06, DRAW-07).
            .savedDrawings(session)
            .notesFileTransfer(session, fileURL: fileURL)
            .drawingsExport(session, fileURL: fileURL)
            // The .slidepilot file with notes, drawings and settings (NOTES-11).
            .slidePilotFileTransfer(session, fileURL: fileURL)
            // Videos and run: links next to the PDF (NAV-06, NAV-07).
            .linkedFiles(session, fileURL: fileURL)
            // The presentation surfaces find the session in the registry (DOC-04).
            .onAppear { registry.register(session) }
            .onDisappear {
                registry.unregister(session.id)
                // The iPad keeps a closed document's state until the next one opens.
                session.documentClosed()
            }
            #if os(iOS)
            // The iPad external display shows the document of the active window.
            .onAppWindowChange { registry.register(session, inWindow: $0) }
            #endif
            #if os(macOS)
            .presenterWindow(for: session)
            #endif
            // The session owns the reload on both platforms (ADR 0013). iPadOS also hands the
            // view a new document after a change, macOS does not, so that copy is ignored.
            .task(id: fileURL) {
                guard let fileURL else { return }
                for await version in PDFFileObserver.versions(of: fileURL, current: session.data) {
                    session.reload(with: version)
                    await session.companion.pdfDidReload(at: fileURL, pageCount: version.info.pageCount)
                }
            }
            // Slide change with keys, menu, toolbar and swipes (NAV-01 to NAV-03).
            .slideNavigationKeys(session)
            .navigatorEscapeKey(session)
            .drawingEscapeKey(session)
            // The "." key must wrap the view that holds the keyboard (CUR-01).
            .blackCurtainKey(session)
    }
}

/// The clock above the slides.
private struct PresenterClock: ViewModifier {
    let session: PresentationSession

    func body(content: Content) -> some View {
        content
            .presenterTimeDisplay(session)
            .finishesNotesEditingOnTap(session.notes)
    }
}

/// The presenter's toolbar items, menu commands and swipes. `SlideNavigatorSplitView` puts
/// them on the slides column (Mac) or on the document's bar (iPad).
private struct PresenterChrome: ViewModifier {
    let session: PresentationSession
    @Environment(\.presenterToolbarFocus) private var focus
    /// Shared by the toolbar's Time menu and the Moderator menu's Set Timer….
    @State private var isSettingTimer = false

    func body(content: Content) -> some View {
        content
            // Every presenter item, in its group (#189).
            .toolbar {
                PresenterToolbar(session: session, focus: focus, isSettingTimer: $isSettingTimer)
            }
            // Layout changes are locked in draw mode (DRAW-05).
            .presenterLayoutControls(session.layout, isLocked: session.drawing.isActive)
            .notesModeControls(session)
            .presenterTimerControls(session, isSettingTimer: $isSettingTimer)
            .presenterNavigation(session)
            .notesEditingControls(session.notes)
            // The "." key for the black curtain (CUR-01).
            .blackCurtainKey(session)
            // "Slide 7 of 18" under the Mac window title (LAY-10).
            .presenterWindowSubtitle(session.position)
            #if os(iOS)
            // The tips above the slides (#82, PTR-01).
            .externalDisplayHint()
            // The Mac has the Settings window instead (SET-01).
            .settingsSheet()
            #endif
            // Above the tips: "Trial Version – … Unlock Pro" while Pro is missing (PRO-05).
            .trialHint()
    }
}
