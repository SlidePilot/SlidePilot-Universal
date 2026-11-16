#if os(iOS)
import SwiftUI
import UIKit

/// Owns the session registry on iPadOS and hands the external-display role to a UIKit
/// scene delegate: SwiftUI has no scene type for it (docs/prototypes/external-display.md).
final class AppDelegate: NSObject, UIApplicationDelegate {
    let registry = SessionRegistry()
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
        DiagnosticsLog.shared.record("ipad: launch, \(application.openSessions.count) open scene session(s)")
        Task { await Self.logSceneChanges() }
        // Lives as long as the app; the app delegate is never released.
        windows.start()
        return true
    }

    /// TEMPORARY (hardware tests for #13): every scene that connects or disconnects,
    /// including SwiftUI's, to see whether iPadOS offers an external-display scene at all.
    private static func logSceneChanges() async {
        let connections = NotificationCenter.default.notifications(named: UIScene.willConnectNotification)
        for await notification in connections {
            guard let scene = notification.object as? UIScene else { continue }
            DiagnosticsLog.shared.record("ipad: scene will connect → \(describe(scene))")
        }
    }

    static func describe(_ scene: UIScene) -> String {
        var text = "role \(scene.session.role.rawValue), config \(scene.session.configuration.name ?? "unnamed")"
        text += ", delegate \(scene.delegate.map { String(describing: type(of: $0)) } ?? "none")"
        if let windowScene = scene as? UIWindowScene {
            let size = windowScene.screen.bounds.size
            text += ", screen \(Int(size.width))×\(Int(size.height)) pt"
            text += ", scenes on device: \(UIApplication.shared.connectedScenes.count)"
        }
        return text
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        DiagnosticsLog.shared.record("ipad: configuration requested for role \(role.rawValue)")
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
        DiagnosticsLog.shared.record("ipad: external display delegate connecting → \(AppDelegate.describe(scene))")
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let registry = AppDelegate.current?.registry else {
            assertionFailure("The app delegate creates the registry before any scene connects.")
            return
        }
        // iPadOS 27: the accessory of one app window, which shows that window's document.
        var appWindow: String?
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            appWindow = connectionOptions.sceneAccessoryUserInfo as? String
        }
        #endif
        DiagnosticsLog.shared.record("ipad: external display for window \(appWindow?.prefix(8) ?? "active")")
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: ExternalDisplayView(appWindow: appWindow).environment(registry))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        DiagnosticsLog.shared.record("ipad: external display shows its window")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        DiagnosticsLog.shared.record("ipad: external display disconnected")
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
