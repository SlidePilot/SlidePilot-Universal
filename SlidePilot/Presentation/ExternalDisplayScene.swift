#if os(iOS)
import OSLog
import SwiftUI
import UIKit

/// Logs the external-display scene's life cycle, so a hardware test can show in the Xcode
/// console why a display mirrors instead of showing the presentation.
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SlidePilot", category: "ExternalDisplay")

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        discardStaleExternalDisplaySessions(of: application)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        log.debug("Configuring a scene for role \(role.rawValue, privacy: .public)")
        guard role == .windowExternalDisplayNonInteractive else {
            return UISceneConfiguration(name: nil, sessionRole: role)
        }
        // Also declared in Config/Info.plist for restored sessions that skip this method.
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: role)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }

    /// iPadOS restores a display's scene session with the configuration it got when it was
    /// created, without asking again. A session from a build without this scene delegate
    /// would keep mirroring the device, so it is discarded and the next connection asks anew.
    private func discardStaleExternalDisplaySessions(of application: UIApplication) {
        for session in application.openSessions where session.role == .windowExternalDisplayNonInteractive {
            let delegateClass: AnyClass? = session.configuration.delegateClass
            log.debug("Restored external display session, delegate \(String(describing: delegateClass), privacy: .public)")
            guard delegateClass != ExternalDisplaySceneDelegate.self else { continue }
            application.requestSceneSessionDestruction(session, options: nil) { error in
                log.error("Could not discard a stale external display session: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Takes over a connected display, cable or AirPlay, at once (DOC-04, DOC-05 changed): the
/// presentation of the most recently active document, or the ready screen.
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log.debug("External display scene connecting")
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
        log.debug("External display scene shows its window")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        log.debug("External display scene disconnected")
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
