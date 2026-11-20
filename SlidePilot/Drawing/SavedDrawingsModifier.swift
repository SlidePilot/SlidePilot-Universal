import SlidePilotCore
import SwiftUI

extension View {
    /// Applies "Save drawings" (DRAW-06) to the document's drawings and keeps them in the
    /// companion file while it is on (DRAW-07).
    func savedDrawings(_ session: PresentationSession) -> some View {
        modifier(SavedDrawingsModifier(session: session))
    }
}

private struct SavedDrawingsModifier: ViewModifier {
    let session: PresentationSession
    /// Missing in snapshots; drawings then behave as with the setting off.
    @Environment(AppSettings.self) private var settings: AppSettings?

    private var savesDrawings: Bool { settings?.savesDrawings ?? false }

    private var drawing: DrawingModel { session.drawing }
    private var companion: DocumentCompanion { session.companion }

    func body(content: Content) -> some View {
        content
            .onAppear {
                drawing.drawings.keepsDrawings = savesDrawings
                drawing.drawings.onPagesChange = { [settings, companion] pages in
                    guard settings?.savesDrawings == true else { return }
                    companion.setDrawings(CompanionDrawings(pages: pages))
                }
            }
            // The entry arrives after opening, and changes when the data of a missing PDF is
            // taken over (NOTES-12).
            .onChange(of: companion.entry?.id, initial: true) {
                loadStoredDrawings()
            }
            .onChange(of: savesDrawings) { _, savesDrawings in
                drawing.drawings.keepsDrawings = savesDrawings
                if savesDrawings {
                    // Drawings made so far, e.g. on the slide in draw mode, are kept from now on.
                    loadStoredDrawings()
                } else {
                    // Turning it off deletes all drawings, like the old app. The settings
                    // view removes those of documents that are not open.
                    drawing.deleteAll()
                    companion.setDrawings(nil)
                }
            }
    }

    /// Shows the stored drawings and stores what was drawn before they arrived. With the
    /// setting off, drops drawings of an entry that was still loading when it was turned off.
    private func loadStoredDrawings() {
        guard companion.entry != nil else { return }
        guard savesDrawings else {
            companion.setDrawings(nil)
            return
        }
        if let stored = companion.drawings {
            drawing.drawings.loadStoredPages(stored.pages)
        }
        companion.setDrawings(CompanionDrawings(pages: drawing.drawings.pages))
    }
}
