#if os(iOS)
import UIKit

/// Registers the external display content on iPadOS 27 (DOC-04, DOC-05 changed).
///
/// iPadOS 27 no longer offers the external-display scene role to apps built with its SDK;
/// content is registered as a scene accessory on a view controller instead (hardware test
/// on an iPad mini with iPadOS 27.2). SwiftUI's `sceneAccessory` modifier only reaches our
/// own views, and while no document is open the window shows the system document browser.
/// So the accessory is registered once on the root view controller of every app window,
/// which stays for the window's lifetime, with or without a document. Its scene uses
/// `ExternalDisplaySceneDelegate`, the same as on iPadOS 26.
@MainActor
final class ExternalDisplayAccessories {
    /// Registrations by scene session, so each app window registers once. Type-erased
    /// because `UISceneAccessoryRegistration` needs iPadOS 27.
    private var registrations: [String: AnyObject] = [:]

    /// Registers the accessory for app windows as they become active, and forgets windows
    /// that close. Runs for the app's lifetime.
    func followAppWindows() async {
        // Xcode 26 (Swift 6.2) has no iPadOS 27 SDK, so this is compiled only by newer compilers.
        #if compiler(>=6.4)
        guard #available(iOS 27, *) else { return }
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: UIScene.didActivateNotification) {
                    guard let scene = notification.object as? UIWindowScene else { continue }
                    await self.register(on: scene)
                }
            }
            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: UIScene.didDisconnectNotification) {
                    guard let scene = notification.object as? UIScene else { continue }
                    await self.forget(scene)
                }
            }
        }
        #endif
    }

    #if compiler(>=6.4)
    @available(iOS 27, *)
    private func register(on scene: UIWindowScene) {
        let id = scene.session.persistentIdentifier
        guard scene.session.role == .windowApplication, registrations[id] == nil,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: .windowExternalDisplayNonInteractive)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        registrations[id] = root.registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
        DiagnosticsLog.shared.record("ipad: external display accessory registered on \(String(describing: type(of: root)))")
    }
    #endif

    private func forget(_ scene: UIScene) {
        registrations[scene.session.persistentIdentifier] = nil
    }
}
#endif
