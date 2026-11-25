#if os(iOS)
import SlidePilotCore
import UIKit

/// Applies the Appearance setting (SET-05) to every app window, including the document
/// browser and sheets. The external display is not an app window and stays dark.
final class AppearanceApplier: AppearanceApplying {
    private var appearance = AppAppearance.default
    private var connections: Task<Void, Never>?

    init() {
        // Windows that open later get the current appearance too. Registered here, so the
        // first window's notification is not missed while the task starts.
        let scenes = NotificationCenter.default.notifications(named: UIScene.willConnectNotification)
        connections = Task { [weak self] in
            for await notification in scenes {
                guard let scene = notification.object as? UIWindowScene else { continue }
                self?.apply(to: scene)
            }
        }
    }

    isolated deinit {
        connections?.cancel()
    }

    func apply(_ appearance: AppAppearance) {
        self.appearance = appearance
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            apply(to: scene)
        }
    }

    private func apply(to scene: UIWindowScene) {
        guard scene.session.role == .windowApplication else { return }
        switch appearance {
        case .system: scene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
        case .light: scene.traitOverrides.userInterfaceStyle = .light
        case .dark: scene.traitOverrides.userInterfaceStyle = .dark
        }
    }
}
#endif
