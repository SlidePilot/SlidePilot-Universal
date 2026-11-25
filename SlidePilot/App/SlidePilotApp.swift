import SlidePilotCore
import SwiftUI

@main
struct SlidePilotApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var registry: SessionRegistry { appDelegate.registry }
    private var settings: AppSettings { appDelegate.settings }
    private var remote: RemoteService { appDelegate.remote }
    private var pro: ProStore { appDelegate.pro }
    #else
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var registry: SessionRegistry
    @State private var presentationWindows = MacPresentationWindows()
    /// The app-wide settings (SET-01), shared by all windows.
    @State private var settings: AppSettings
    /// Keeps the display awake while the app runs, if the setting is on (SET-04).
    @State private var displayAwakeKeeper: DisplayAwakeKeeper
    /// Applies the Appearance setting to all windows while the app runs (SET-05).
    @State private var appearanceKeeper: AppearanceKeeper
    /// Advertises this instance and keeps pairing state (REM-02); one per app.
    @State private var remote: RemoteService
    /// The Pro status and purchase (PRO-02); one per app.
    @State private var pro: ProStore

    init() {
        let settings = AppSettings(store: UserDefaults.standard)
        let registry = SessionRegistry()
        _registry = State(initialValue: registry)
        _settings = State(initialValue: settings)
        _displayAwakeKeeper = State(initialValue: DisplayAwakeKeeper(settings: settings, blocker: DisplaySleepBlocker()))
        _appearanceKeeper = State(initialValue: AppearanceKeeper(settings: settings, applier: AppearanceApplier()))
        _remote = State(initialValue: RemoteService.live(settings: settings, registry: registry))
        // Listens for transactions from launch on, so none is missed (PRO-02).
        let pro = ProStore()
        pro.start()
        _pro = State(initialValue: pro)
        // Like the old app: the presenter and presentation windows never merge into tabs (DOC-04).
        NSWindow.allowsAutomaticWindowTabbing = false
        CompanionStore.cleanUpAtLaunch()
        // Copies of embedded videos that a crash or force quit left behind (#142).
        EmbeddedFileStore.removeLeftovers()
    }
    #endif

    var body: some Scene {
        // One window per PDF (DOC-01/02). The system provides the open panel at launch,
        // File ▸ Open, Open Recent and Close on the Mac and the document browser on iPad.
        // The document window is the presenter (DOC-04).
        #if os(macOS)
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                // Pairing codes of devices that start controlling this one (REM-02).
                .remoteAlerts()
                // Free Mac download only (DROP-03).
                .donationHint(appDelegate.donationHint)
                .environment(registry)
                .environment(presentationWindows)
                .environment(appDelegate.companions)
                // Padding and time display size of the presenter (LAY-04, TIME-06).
                .environment(settings)
                .environment(remote)
                .environment(pro)
        }
        .commands {
            PresentationCommands()
            LayoutCommands()
            ModeratorCommands()
            NotesFormatCommands()
            NotesFileCommands()
            DrawingsExportCommands()
            SlidePilotFileCommands()
            RemoteControlCommands()
            HelpCommands()
            DonationCommands()
        }
        // A new presenter window opens at 1400 × 900, or the visible screen if that is smaller;
        // restored windows keep their frame (DOC-04). DocumentGroup ignores defaultWindowPlacement,
        // so the size is set here and the system centers the window.
        .defaultSize(PresenterWindowSize.size(forVisibleScreen: NSScreen.main?.visibleFrame.size ?? .zero))

        // A .slidepilot file opened on its own, imported into a PDF (NOTES-11).
        DocumentGroup(viewing: SlidePilotFileDocument.self) { file in
            SlidePilotFileView(document: file.document, fileURL: file.fileURL)
                .environment(registry)
                .environment(appDelegate.companions)
                .environment(settings)
        }
        .windowResizability(.contentSize)

        // Remote mode: controls a presentation on another device (REM-07, ADR 0015).
        WindowGroup(Text("Remote Control"), id: RemoteControlScene.id) {
            RemoteControlView()
                .environment(remote)
                .environment(settings)
                .environment(pro)
                .frame(minWidth: 480, minHeight: 360)
        }
        .restorationBehavior(.disabled)
        // Opened with File ▸ Control Another Device…, not File ▸ New.
        .commandsRemoved()

        // The presentation window of each document (DOC-04 to DOC-06). It is opened by the
        // presenter, never restored at launch and has no File ▸ New command.
        WindowGroup(Text("Presentation"), id: PresentationScene.id, for: PresentationSession.ID.self) { $id in
            PresentationWindowContent(id: id)
                .environment(registry)
                .environment(presentationWindows)
                .environment(settings)
                .environment(pro)
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
                .environment(pro)
                .environment(appDelegate.companions)
        }
        #else
        // The external display: a UIKit scene (ExternalDisplayScene.swift), offered by the
        // system up to iPadOS 26 and registered as a scene accessory from iPadOS 27
        // (AppWindowTracker.swift).
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                // Pairing codes of devices that start controlling this one (REM-02).
                .remoteAlerts()
                .environment(registry)
                .environment(appDelegate.externalDisplays)
                .environment(appDelegate.companions)
                .environment(settings)
                .environment(remote)
                .environment(pro)
        }
        .commands {
            PresentationCommands()
            ModeratorCommands()
            SettingsCommands()
            HelpCommands()
        }
        .commands {
            LayoutCommands()
            NotesFormatCommands()
            NotesFileCommands()
            DrawingsExportCommands()
            SlidePilotFileCommands()
        }

        // A .slidepilot file opened on its own, imported into a PDF (NOTES-11).
        DocumentGroup(viewing: SlidePilotFileDocument.self) { file in
            SlidePilotFileView(document: file.document, fileURL: file.fileURL)
                .environment(registry)
                .environment(appDelegate.companions)
                .environment(settings)
        }

        // The document browser offers remote mode below the app name (REM-07). It opens in
        // the same window, over the browser.
        DocumentGroupLaunchScene {
            // No pairing alerts here: the launch scene cannot present them, so pairing
            // requests are only accepted while a document or remote mode is shown.
            ControlAnotherDeviceButton()
                .environment(remote)
                .environment(settings)
                .environment(pro)
        }

        #endif
    }
}
