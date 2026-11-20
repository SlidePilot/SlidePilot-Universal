import SlidePilotCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CompanionStore {
    /// The app's companion entries in Application Support (ADR 0012). `nil` if the folder
    /// cannot be created; documents then open without stored data.
    static let app: CompanionStore? = try? CompanionStore.appContainer()

    /// Removes settings-only entries that were not opened for 12 months (SET-03).
    static func cleanUpAtLaunch() {
        guard let app else { return }
        Task { await app.removeExpiredEntries() }
    }
}

/// The companions of the open documents, so the Mac can save them before the app quits and
/// the stored data overview (SET-07) can delete an open document's data.
@MainActor
@Observable
final class OpenCompanions {
    @ObservationIgnored private var companions: [ObjectIdentifier: DocumentCompanion] = [:]

    func add(_ companion: DocumentCompanion) {
        companions[ObjectIdentifier(companion)] = companion
    }

    func remove(_ companion: DocumentCompanion) {
        companions[ObjectIdentifier(companion)] = nil
    }

    var all: [DocumentCompanion] { Array(companions.values) }

    func flushAll() async {
        for companion in companions.values {
            await companion.flush()
        }
    }
}

extension View {
    /// Loads and saves the document's companion entry: per-document settings (SET-02), the
    /// orphaned data hint (NOTES-12) and the document-edited indicator (DOC-09).
    func companionFile(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(CompanionFileModifier(session: session, fileURL: fileURL))
    }
}

private struct CompanionFileModifier: ViewModifier {
    let session: PresentationSession
    let fileURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    /// The Mac saves these before quitting; iPadOS saves when the app leaves the foreground.
    @Environment(OpenCompanions.self) private var openCompanions: OpenCompanions?
    #if os(macOS)
    /// A reference, not a value: storing the window must not redraw the document window.
    @State private var windowReference = WindowReference()
    #endif

    private var companion: DocumentCompanion { session.companion }

    func body(content: Content) -> some View {
        content
            // Settings are applied at the end of opening (SET-02). Layout changes are stored
            // only from then on: while the window builds up, the Mac split view reports its
            // separator position, which would save the last-used layout over the stored one.
            .task(id: fileURL) {
                guard let fileURL else { return }
                let settings = await companion.open(pdfAt: fileURL, pageCount: session.cache.info.pageCount)
                guard !Task.isCancelled else { return }
                if let settings {
                    apply(settings)
                }
                session.layout.onChange = { [companion] layout in
                    companion.updateSettings { $0.layout = layout }
                }
            }
            // The navigator is a per-document setting like in the old app (SET-02, LAY-06).
            .onChange(of: session.isNavigatorDisplayed) { _, isDisplayed in
                companion.updateSettings { $0.isNavigatorDisplayed = isDisplayed }
            }
            // So are the pointer's display state and appearance (PTR-07).
            .onChange(of: session.pointer.isShown) { _, isShown in
                companion.updateSettings { $0.isPointerDisplayed = isShown }
            }
            .onChange(of: session.pointer.appearance) { _, appearance in
                companion.updateSettings { $0.pointerAppearance = appearance }
            }
            // Stored only once changed, so the PDF's keywords keep applying until then (NOTES-03).
            .onChange(of: session.notesDisplay) { _, display in
                companion.updateSettings {
                    $0.notesMode = display.mode
                    $0.notesPosition = display.position
                }
            }
            .alert(
                Text("Use Data from a Missing PDF?"),
                isPresented: Binding(get: { companion.orphan != nil }, set: { _ in }),
                presenting: companion.orphan
            ) { _ in
                Button("Use Data") {
                    Task {
                        if let settings = await companion.takeOverOrphan() {
                            apply(settings)
                        }
                    }
                }
                Button("Don’t Use", role: .cancel) {
                    Task { await companion.declineOrphan() }
                }
            } message: { orphan in
                Text("A PDF named “\(orphan.pdf.fileName)” with the same number of pages can no longer be found. You can use its stored data for this PDF.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    saveInBackground(companion)
                }
            }
            .onAppear { openCompanions?.add(companion) }
            .onDisappear {
                // Removed only after the save, so quitting right after closing still waits for it.
                saveInBackground(companion) { [openCompanions] in
                    openCompanions?.remove(companion)
                }
            }
            #if os(macOS)
            // The presenter window shows the system's edited dot in its close button (DOC-09).
            .background(WindowBridge { newWindow in
                windowReference.window = newWindow
                newWindow.isDocumentEdited = companion.isEdited
            })
            .onChange(of: companion.isEdited) { _, isEdited in
                windowReference.window?.isDocumentEdited = isEdited
            }
            #endif
    }

    /// Saves pending changes. On iPadOS the system keeps the app running until the write
    /// finished, also when it moves to the background.
    private func saveInBackground(_ companion: DocumentCompanion, then completion: @escaping @MainActor () -> Void = {}) {
        #if os(iOS)
        let application = UIApplication.shared
        let backgroundTask = BackgroundTask()
        backgroundTask.id = application.beginBackgroundTask(withName: "Save document data") {
            // Out of time: end the task, so the system suspends the app instead of ending it.
            backgroundTask.end()
        }
        Task {
            await companion.flush()
            completion()
            backgroundTask.end()
        }
        #else
        Task {
            await companion.flush()
            completion()
        }
        #endif
    }

    private func apply(_ settings: DocumentSettings) {
        if let layout = settings.layout {
            session.layout.applyStoredLayout(layout)
        }
        if let isNavigatorDisplayed = settings.isNavigatorDisplayed {
            session.isNavigatorDisplayed = isNavigatorDisplayed
        }
        if let isPointerDisplayed = settings.isPointerDisplayed {
            session.pointer.isShown = isPointerDisplayed
        }
        if let pointerAppearance = settings.pointerAppearance {
            session.pointer.appearance = pointerAppearance
        }
        session.applyStoredNotesDisplay(mode: settings.notesMode, position: settings.notesPosition)
    }
}

#if os(iOS)
/// The identifier of a background task, shared by the save and the expiration handler.
private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

#if os(macOS)
/// The presenter window of a document, for the edited dot (DOC-09).
private final class WindowReference {
    weak var window: NSWindow?
}
#endif
