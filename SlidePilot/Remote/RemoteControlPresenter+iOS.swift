#if os(iOS)
import SlidePilotCore
import SwiftUI
import UIKit

/// Shows remote mode full screen over the document browser of the active window (REM-07).
/// The document launch scene only runs the action of its buttons and cannot present a
/// SwiftUI sheet, so this presents a hosting controller from UIKit.
enum RemoteControlPresenter {
    static func present(remote: RemoteService, settings: AppSettings, pro: ProStore) {
        guard let presenter = LaunchScreenPresenter.topViewController() else { return }
        let host = UIHostingController<PresentedRemoteControl?>(rootView: nil)
        host.rootView = PresentedRemoteControl(remote: remote, settings: settings, pro: pro) { [weak host] in
            host?.dismiss(animated: true)
        }
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }
}

/// Finds where the launch screen's actions can present UIKit views.
enum LaunchScreenPresenter {
    /// The top view controller of the active window.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let scene = scenes.first(where: { $0.keyWindow?.isKeyWindow == true }) ?? scenes.first,
              var presenter = scene.keyWindow?.rootViewController
        else { return nil }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}

private struct PresentedRemoteControl: View {
    let remote: RemoteService
    let settings: AppSettings
    let pro: ProStore
    let close: () -> Void

    var body: some View {
        RemoteControlView(close: close)
            .environment(remote)
            .environment(settings)
            .environment(pro)
    }
}
#endif
