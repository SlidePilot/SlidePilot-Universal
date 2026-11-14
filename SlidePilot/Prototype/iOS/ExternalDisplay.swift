#if os(iOS)
import SwiftUI
import UIKit

// PROTOTYPE (issue #7). SwiftUI has no scene type for the external-display role,
// so the app delegate hands that role to a small UIKit scene delegate that hosts
// the SwiftUI PresentationView.

final class PrototypeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        PrototypeSession.shared.record("ipad: scene requested, role \(role.rawValue)")
        // The external-display configuration is also declared in Config/Info.plist.
        let name: String? = role == .windowExternalDisplayNonInteractive ? "External Display" : nil
        let configuration = UISceneConfiguration(name: name, sessionRole: role)
        if role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        for session in sceneSessions {
            PrototypeSession.shared.record("ipad: scene session discarded, role \(session.role.rawValue)")
        }
    }
}

final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    private var session: PrototypeSession { .shared }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: PresentationView(session: self.session, host: "ipad external display scene"))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        self.session.externalDisplayScenes += 1
        self.session.record("ipad: external display scene connected → \(IPadDisplayDescription.describe(windowScene))")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        session.externalDisplayScenes = max(0, session.externalDisplayScenes - 1)
        session.record("ipad: external display scene disconnected")
        window = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        session.record("ipad: external display scene active")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        session.record("ipad: external display scene will resign active")
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        session.record("ipad: external display geometry changed → \(IPadDisplayDescription.describe(windowScene))")
    }
}

enum IPadDisplayDescription {
    static func describe(_ scene: UIWindowScene) -> String {
        let screen = scene.screen
        let bounds = screen.bounds.size
        let native = screen.nativeBounds.size
        let role: String = switch scene.session.role {
        case .windowApplication: "application"
        case .windowExternalDisplayNonInteractive: "external display"
        default: scene.session.role.rawValue
        }
        let state: String = switch scene.activationState {
        case .foregroundActive: "active"
        case .foregroundInactive: "inactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "unknown"
        }
        let geometry = scene.effectiveGeometry
        var text = "\(role), \(state), screen \(Int(bounds.width))×\(Int(bounds.height)) pt @\(screen.scale.formatted())x"
            + " (native \(Int(native.width))×\(Int(native.height)) px @\(screen.nativeScale.formatted())x)"
            + ", scene \(Int(geometry.coordinateSpace.bounds.width))×\(Int(geometry.coordinateSpace.bounds.height)) pt"
            + ", \(screen.maximumFramesPerSecond) fps"
        if screen.mirrored != nil { text += ", MIRRORING" }
        // Shows whether our scene delegate is attached or iPadOS/SwiftUI used another one.
        text += ", delegate \(scene.delegate.map { String(describing: type(of: $0)) } ?? "none")"
        text += ", config \(scene.session.configuration.name ?? "unnamed")"
        if scene.isFullScreen { text += ", full screen" }
        if screen == UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.session.role == .windowApplication })?.screen {
            text += ", device screen"
        }
        return text
    }

    static func connectedScenes() -> [String] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { describe($0) }
            .sorted()
    }
}

// MARK: Platform hooks

struct PresenterPlatformModifier: ViewModifier {
    let session: PrototypeSession

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Label {
                    Text(verbatim: session.externalDisplayScenes > 0
                        ? "Presentation on external display"
                        : "No external display scene")
                } icon: {
                    Image(systemName: session.externalDisplayScenes > 0 ? "display" : "display.trianglebadge.exclamationmark")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
            }
            .onAppear { session.record("ipad: presenter appeared → \(IPadDisplayDescription.connectedScenes().joined(separator: " | "))") }
    }
}

struct PresentationPlatformModifier: ViewModifier {
    let session: PrototypeSession

    func body(content: Content) -> some View {
        content
            .persistentSystemOverlays(.hidden)
            .statusBarHidden()
    }
}

struct PlatformDiagnostics: View {
    let session: PrototypeSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(IPadDisplayDescription.connectedScenes(), id: \.self) { Text(verbatim: $0) }
                }
                .font(.caption.monospaced())
            }
            Button { openWindow(id: PrototypeScene.presentationID) } label: {
                Text(verbatim: "Open Presentation as Window (extended display)")
            }
            Button {
                session.record("ipad: snapshot → \(IPadDisplayDescription.connectedScenes().joined(separator: " | "))")
            } label: {
                Text(verbatim: "Log Current State")
            }
        } header: {
            Text(verbatim: "Scenes")
        }
    }
}

func copyToPasteboard(_ text: String) {
    UIPasteboard.general.string = text
}
#endif
