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
    private lazy var windows = AppWindowTracker(registry: registry)

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
        // Fails only if called twice; without it the external-display tip stays hidden.
        try? Tips.configure()
        CompanionStore.cleanUpAtLaunch()
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
        let host = UIHostingController(rootView: ExternalDisplayView(appWindow: appWindow).environment(registry))
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
