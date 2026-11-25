#if os(iOS)
import SlidePilotCore
import SwiftUI
import TipKit
import UIKit

/// Owns the session registry on iPadOS and hands the external-display role to a UIKit
/// scene delegate: SwiftUI has no scene type for it (docs/prototypes/external-display.md).
final class AppDelegate: NSObject, UIApplicationDelegate {
    let registry = SessionRegistry()
    let externalDisplays = ExternalDisplayStatus()
    /// The open documents' companions, for the stored data overview (SET-07).
    let companions = OpenCompanions()
    /// The app-wide settings (SET-01), here so the external display can read them too.
    let settings = AppSettings(store: UserDefaults.standard)
    /// Keeps the display awake while the app runs, if the setting is on (SET-04).
    private lazy var displayAwakeKeeper = DisplayAwakeKeeper(settings: settings, blocker: DisplaySleepBlocker())
    /// Advertises this instance and keeps pairing state (REM-02); one per app.
    private(set) lazy var remote = RemoteService.live(settings: settings, registry: registry, pro: pro)
    /// The Pro status and purchase (PRO-02); one per app, also read by the external display.
    let pro = ProStore()
    private lazy var windows = AppWindowTracker(registry: registry)
    /// Applies the Appearance setting to all app windows (SET-05).
    private lazy var appearanceKeeper = AppearanceKeeper(settings: settings, applier: AppearanceApplier())

    /// The only global path to the app-owned registry: UIKit creates scene delegates by
    /// class, so there is no other way to hand it to the external-display scene.
    private(set) static weak var current: AppDelegate?

    override init() {
        super.init()
        Self.current = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Lives as long as the app; the app delegate is never released.
        windows.start()
        _ = displayAwakeKeeper
        _ = appearanceKeeper
        _ = remote
        // Listens for transactions from launch on, so none is missed (PRO-02).
        pro.start()
        // Fails only if called twice; without it the external-display tip stays hidden.
        try? Tips.configure()
        CompanionStore.cleanUpAtLaunch()
        // Copies of embedded videos that a crash or force quit left behind (#142).
        EmbeddedFileStore.removeLeftovers()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        guard role == .windowExternalDisplayNonInteractive else {
            return UISceneConfiguration(name: nil, sessionRole: role)
        }
        // Also declared in Config/Info.plist for restored sessions that skip this method.
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: role)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }
}

/// Takes over a connected display, cable or AirPlay, at once (DOC-04, DOC-05 changed): the
/// presentation of the document in the active app window, or the ready screen.
/// See `AppWindowTracker` for how iPadOS 26 and 27 connect it.
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let app = AppDelegate.current else {
            assertionFailure("The app delegate creates the registry before any scene connects.")
            return
        }
        let registry = app.registry
        app.externalDisplays.connect(session.persistentIdentifier)
        // Users who connected a display once know how; the tip never comes back (#82).
        ExternalDisplayTip().invalidate(reason: .actionPerformed)
        // iPadOS 27: the accessory of one app window, which shows that window's document.
        var appWindow: String?
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            appWindow = connectionOptions.sceneAccessoryUserInfo as? String
        }
        #endif
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: ExternalDisplayView(appWindow: appWindow).environment(registry).environment(app.settings).environment(app.pro))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppDelegate.current?.externalDisplays.disconnect(scene.session.persistentIdentifier)
        window = nil
    }
}

/// What the external display shows: a document's presentation or the ready screen.
struct ExternalDisplayView: View {
    /// The app window whose document is shown; `nil` follows the active window.
    var appWindow: String?
    @Environment(SessionRegistry.self) private var registry

    private var session: PresentationSession? {
        if let appWindow { registry.session(inWindow: appWindow) } else { registry.activeSession }
    }

    var body: some View {
        Group {
            if let session {
                PresentationView(session: session)
            } else {
                ReadyToPresentView()
            }
        }
        .persistentSystemOverlays(.hidden)
    }
}
#endif
