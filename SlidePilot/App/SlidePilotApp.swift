import SlidePilotCore
import SwiftUI

@main
struct SlidePilotApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var registry: SessionRegistry { appDelegate.registry }
    #else
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var registry = SessionRegistry()
    @State private var presentationWindows = MacPresentationWindows()
    #endif
    /// The app-wide settings (SET-01), shared by all windows.
    @State private var settings: AppSettings
    /// Advertises this instance and keeps pairing state (REM-02); one per app.
    @State private var remote: RemoteService

    init() {
        #if os(macOS)
        // Like the old app: the presenter and presentation windows never merge into tabs (DOC-04).
        NSWindow.allowsAutomaticWindowTabbing = false
        CompanionStore.cleanUpAtLaunch()
        #if DEBUG
        TestHostAppearance.apply()
        #endif
        #endif
        let settings = AppSettings(store: UserDefaults.standard)
        _settings = State(initialValue: settings)
        _remote = State(initialValue: RemoteService.live(settings: settings))
    }

    var body: some Scene {
        // One window per PDF (DOC-01/02). The system provides the open panel at launch,
        // File ▸ Open, Open Recent and Close on the Mac and the document browser on iPad.
        // The document window is the presenter (DOC-04).
        #if os(macOS)
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                .environment(registry)
                .environment(presentationWindows)
                .environment(appDelegate.companions)
        }
        .commands {
            PresentationCommands()
            LayoutCommands()
            ModeratorCommands()
        }

        // The presentation window of each document (DOC-04 to DOC-06). It is opened by the
        // presenter, never restored at launch and has no File ▸ New command.
        WindowGroup(Text("Presentation"), id: PresentationScene.id, for: PresentationSession.ID.self) { $id in
            PresentationWindowContent(id: id)
                .environment(registry)
                .environment(presentationWindows)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .defaultWindowPlacement { _, _ in
            presentationWindows.placement()
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(remote)
        }
        #else
        // The external display: a UIKit scene (ExternalDisplayScene.swift), offered by the
        // system up to iPadOS 26 and registered as a scene accessory from iPadOS 27
        // (AppWindowTracker.swift).
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                .environment(registry)
                .environment(appDelegate.externalDisplays)
                .environment(settings)
                .environment(remote)
        }
        .commands {
            PresentationCommands()
            ModeratorCommands()
            SettingsCommands()
        }
        .commands {
            LayoutCommands()
        }

        #endif
    }
}
