#if os(iOS)
import SwiftUI
import UIKit

/// Connects the app windows on iPadOS to the external display (DOC-04, DOC-05 changed).
///
/// An app window is identified by its scene session. The external display shows the
/// document of the window the user works in, or the ready screen if that window shows none:
/// - Up to iPadOS 26, the system offers one external-display scene. It follows the key
///   window, because with several visible windows the scene phase does not change on a switch.
/// - iPadOS 27 no longer offers that scene role to apps built with its SDK; content is
///   registered as a scene accessory on a view controller instead (hardware test on an iPad
///   mini with iPadOS 27.2), and the system presents the accessory of the window in front.
///   SwiftUI's `sceneAccessory` modifier only reaches our own views, and while no document
///   is open the window shows the system document browser. So the accessory is registered
///   once on the root view controller of every app window, which stays for the window's
///   lifetime, and carries the window's ID. Its scene uses `ExternalDisplaySceneDelegate`,
///   the same as on iPadOS 26. While iPadOS swaps the accessories on a window switch or at
///   launch, the display briefly mirrors the device (hardware test); a single accessory
///   for all windows was tried and is not presented for the other windows.
@MainActor
final class AppWindowTracker {
    private let registry: SessionRegistry
    /// Accessory registrations by window, so each window registers once. Type-erased
    /// because `UISceneAccessoryRegistration` needs iPadOS 27.
    private var registrations: [String: AnyObject] = [:]

    init(registry: SessionRegistry) {
        self.registry = registry
    }

    static func id(of scene: UIScene) -> String? {
        scene.session.role == .windowApplication ? scene.session.persistentIdentifier : nil
    }

    /// Starts following the app windows for the app's lifetime. Call it at launch, before
    /// the first window connects: the observers are registered right here, so the first
    /// window's notifications are not missed while the task starts.
    func start() {
        let center = NotificationCenter.default
        let keyWindows = center.notifications(named: UIWindow.didBecomeKeyNotification)
        // Xcode 26 (Swift 6.2) has no iPadOS 27 SDK, so this is compiled only by newer compilers.
        #if compiler(>=6.4)
        let usesAccessories: Bool
        if #available(iOS 27, *) { usesAccessories = true } else { usesAccessories = false }
        // On activation, because the root view controller may not exist yet when a window connects.
        let activations = center.notifications(named: UIScene.didActivateNotification)
        let disconnections = center.notifications(named: UIScene.didDisconnectNotification)
        #endif
        Task {
            await withDiscardingTaskGroup { group in
                group.addTask {
                    for await notification in keyWindows {
                        guard let window = notification.object as? UIWindow else { continue }
                        await self.activate(window)
                    }
                }
                #if compiler(>=6.4)
                guard usesAccessories, #available(iOS 27, *) else { return }
                group.addTask {
                    for await notification in activations {
                        guard let scene = notification.object as? UIWindowScene else { continue }
                        await self.registerAccessory(on: scene)
                    }
                }
                group.addTask {
                    for await notification in disconnections {
                        guard let scene = notification.object as? UIScene else { continue }
                        await self.forget(scene)
                    }
                }
                #endif
            }
        }
    }

    private func activate(_ window: UIWindow) {
        guard let scene = window.windowScene, let id = Self.id(of: scene) else { return }
        registry.activateWindow(id)
    }

    #if compiler(>=6.4)
    @available(iOS 27, *)
    private func registerAccessory(on scene: UIWindowScene) {
        // Skips a scene that disconnected meanwhile, so `forget` stays its last word.
        guard scene.activationState != .unattached, let id = Self.id(of: scene), registrations[id] == nil,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: .windowExternalDisplayNonInteractive)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        registrations[id] = root.registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration, userInfo: id))
    }

    @available(iOS 27, *)
    private func forget(_ scene: UIScene) {
        registrations[scene.session.persistentIdentifier] = nil
    }
    #endif
}

extension View {
    /// Calls `action` with the ID of the app window that shows this view, whenever the view
    /// moves into a window.
    func onAppWindowChange(_ action: @escaping (String) -> Void) -> some View {
        background(AppWindowReader(action: action))
    }
}

private struct AppWindowReader: UIViewRepresentable {
    let action: (String) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.action = action
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.action = action
    }

    final class ReaderView: UIView {
        var action: ((String) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene, let id = AppWindowTracker.id(of: scene) else { return }
            action?(id)
        }
    }
}
#endif
