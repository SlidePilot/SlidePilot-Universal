#if os(iOS)
import SwiftUI
import UIKit

/// Owns the session registry on iPadOS and hands the external-display role to a UIKit
/// scene delegate: SwiftUI has no scene type for it (docs/prototypes/external-display.md).
final class AppDelegate: NSObject, UIApplicationDelegate {
    let registry = SessionRegistry()

    /// The only global path to the app-owned registry: UIKit creates scene delegates by
    /// class, so there is no other way to hand it to the external-display scene.
    private(set) static weak var current: AppDelegate?

    override init() {
        super.init()
        Self.current = self
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
/// presentation of the most recently active document, or the ready screen.
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let registry = AppDelegate.current?.registry else {
            assertionFailure("The app delegate creates the registry before any scene connects.")
            return
        }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: ExternalDisplayView().environment(registry))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
    }
}

private struct ExternalDisplayView: View {
    @Environment(SessionRegistry.self) private var registry

    var body: some View {
        Group {
            if let session = registry.activeSession {
                PresentationView(session: session)
            } else {
                ReadyToPresentView()
            }
        }
        .persistentSystemOverlays(.hidden)
    }
}
#endif
