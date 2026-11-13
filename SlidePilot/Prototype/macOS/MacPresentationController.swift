#if os(macOS)
import AppKit
import SwiftUI

// PROTOTYPE (issue #7). AppKit glue for things SwiftUI cannot do on macOS 26:
// choose a specific screen, enter full screen, keep the presenter key, react to
// screens being added or removed.

enum MacPlacementStrategy: String, CaseIterable, Identifiable {
    /// Like the old app: set the frame to `NSScreen.screens[1]` through the NSWindow.
    case appKit
    /// SwiftUI `defaultWindowPlacement` (only knows the default display), then full screen.
    case swiftUI

    var id: Self { self }

    var title: String {
        switch self {
        case .appKit: "A: AppKit setFrame (old app)"
        case .swiftUI: "B: SwiftUI defaultWindowPlacement"
        }
    }

    static let storageKey = "prototype.macPlacementStrategy"
    static var current: MacPlacementStrategy {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MacPlacementStrategy.init(rawValue:)) ?? .appKit
    }
}

enum MacPrototypeSettings {
    static let autoMoveKey = "prototype.macAutoMoveOnScreenAdded"
    static let fullScreenKey = "prototype.macEnterFullScreen"
}

final class MacPresentationController {
    /// Prototype shortcut (see `PrototypeSession.shared`).
    static let shared = MacPresentationController()

    weak var presenterWindow: NSWindow?
    private(set) weak var presentationWindow: NSWindow?

    private var session: PrototypeSession { .shared }
    private var appObservers: [NSObjectProtocol] = []
    private var windowObservers: [NSObjectProtocol] = []
    private var lastScreenCount = NSScreen.screens.count
    private var fullScreenExits = 0
    private var needsPlacement = true
    private var isMoving = false

    // MARK: Screen observation

    func startObservingScreens() {
        guard appObservers.isEmpty else { return }
        session.record("mac: launch with \(Self.screensSummary())")
        appObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // queue: .main delivers on the main thread.
                MainActor.assumeIsolated { self?.screensDidChange() }
            }
        )
    }

    private func screensDidChange() {
        let count = NSScreen.screens.count
        let previous = lastScreenCount
        lastScreenCount = count
        session.record("mac: screen parameters changed → \(Self.screensSummary())")
        Task {
            // Let AppKit finish moving windows before reading where they ended up.
            try? await Task.sleep(for: .seconds(1.5))
            session.record("mac: 1.5 s after change → \(windowsSummary())")
            if count > previous, UserDefaults.standard.bool(forKey: MacPrototypeSettings.autoMoveKey),
               let window = presentationWindow, Self.index(of: window.screen) == 0, count >= 2
            {
                session.record("mac: auto-move presentation to screen #1")
                await movePresentation(toScreen: 1)
            }
        }
    }

    // MARK: Windows

    func attachPresenter(_ window: NSWindow) {
        guard presenterWindow !== window else { return }
        presenterWindow = window
        session.record("mac: presenter window on \(Self.describe(window.screen))")
    }

    func attachPresentation(_ window: NSWindow) {
        if presentationWindow !== window {
            presentationWindow = window
            observe(window)
        }
        placeIfNeeded()
    }

    /// Called on attach and on every appearance: SwiftUI's `Window` scene may reuse the
    /// same NSWindow after it was closed, so placement is keyed to "opened", not to the window.
    func placeIfNeeded() {
        guard needsPlacement, let window = presentationWindow else { return }
        needsPlacement = false
        let strategy = MacPlacementStrategy.current
        session.record(
            "mac: presentation window created on \(Self.describe(window.screen)), "
                + "frame \(Self.describe(window.frame)), strategy \(strategy.rawValue), key: \(keyWindowName())"
        )
        Task {
            // The window is not fully set up while SwiftUI attaches its views.
            try? await Task.sleep(for: .milliseconds(150))
            if strategy == .appKit, NSScreen.screens.count >= 2 {
                window.setFrame(NSScreen.screens[1].visibleFrame, display: true)
                session.record("mac: setFrame to screen #1 → now on \(Self.describe(window.screen))")
            }
            if UserDefaults.standard.object(forKey: MacPrototypeSettings.fullScreenKey) as? Bool ?? true {
                window.collectionBehavior.insert(.fullScreenPrimary)
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
            presenterWindow?.makeKeyAndOrderFront(nil)
            session.record("mac: after placement key window: \(keyWindowName())")
        }
    }

    private func observe(_ window: NSWindow) {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        let events: [(Notification.Name, String)] = [
            (NSWindow.didChangeScreenNotification, "moved to another screen"),
            (NSWindow.didEnterFullScreenNotification, "entered full screen"),
            (NSWindow.didExitFullScreenNotification, "exited full screen"),
            (NSWindow.didBecomeKeyNotification, "became key"),
            (NSWindow.willCloseNotification, "will close"),
        ]
        for (name, text) in events {
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    // queue: .main delivers on the main thread.
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if name == NSWindow.didExitFullScreenNotification { self.fullScreenExits += 1 }
                        if name == NSWindow.willCloseNotification { self.needsPlacement = true }
                        self.session.record("mac: presentation window \(text) → \(Self.describe(self.presentationWindow?.screen))")
                    }
                }
            )
        }
    }

    /// Manual move used by the diagnostics buttons and the auto-move option.
    func movePresentation(toScreen index: Int) async {
        guard let window = presentationWindow, index < NSScreen.screens.count else {
            session.record("mac: move failed: no presentation window or screen #\(index)")
            return
        }
        // Two overlapping moves would toggle full screen against each other.
        guard !isMoving else {
            session.record("mac: move to screen #\(index) ignored, another move is running")
            return
        }
        isMoving = true
        defer { isMoving = false }
        let wasFullScreen = window.styleMask.contains(.fullScreen)
        if wasFullScreen {
            let exits = fullScreenExits
            window.toggleFullScreen(nil)
            // Wait for the exit animation; a frame change during it is ignored.
            for _ in 0..<60 where fullScreenExits == exits {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        window.setFrame(NSScreen.screens[index].visibleFrame, display: true)
        if wasFullScreen {
            window.toggleFullScreen(nil)
        }
        presenterWindow?.makeKeyAndOrderFront(nil)
        session.record("mac: moved presentation to screen #\(index) → \(Self.describe(window.screen))")
    }

    func toggleFullScreen() {
        presentationWindow?.toggleFullScreen(nil)
    }

    // MARK: Descriptions (no display names: they can identify devices)

    static func index(of screen: NSScreen?) -> Int? {
        guard let screen else { return nil }
        return NSScreen.screens.firstIndex(of: screen)
    }

    static func describe(_ screen: NSScreen?) -> String {
        guard let screen, let index = index(of: screen) else { return "no screen" }
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        var text = "#\(index) \(Int(size.width))×\(Int(size.height)) pt @\(scale.formatted())x "
            + "(\(Int(size.width * scale))×\(Int(size.height * scale)) px)"
        if index == 0 { text += " menu bar" }
        if screen == NSScreen.main { text += " key" }
        return text
    }

    static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height)))"
    }

    static func screensSummary() -> String {
        let screens = NSScreen.screens
        return "\(screens.count) screen(s): " + screens.map { describe($0) }.joined(separator: "; ")
    }

    func windowsSummary() -> String {
        let presentation = presentationWindow.map {
            "presentation on \(Self.describe($0.screen))\($0.styleMask.contains(.fullScreen) ? " full screen" : " windowed")"
                + "\($0.isVisible ? "" : " hidden")"
        } ?? "no presentation window"
        let presenter = presenterWindow.map { "presenter on \(Self.describe($0.screen))" } ?? "no presenter window"
        return "\(presentation); \(presenter); key: \(keyWindowName())"
    }

    func keyWindowName() -> String {
        guard let key = NSApp.keyWindow else { return "none" }
        if key === presentationWindow { return "presentation" }
        if key === presenterWindow { return "presenter" }
        return "other"
    }
}

/// Hands the hosting NSWindow to a closure once the view is in a window.
struct WindowBridge: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(onAttach: onAttach)
    }

    func updateNSView(_ view: BridgeView, context: Context) {}

    final class BridgeView: NSView {
        let onAttach: (NSWindow) -> Void

        init(onAttach: @escaping (NSWindow) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttach(window) }
        }
    }
}

/// SwiftUI placement for strategy B. `WindowPlacementContext` only exposes the
/// default display, so the target screen still has to come from `NSScreen`.
enum MacSwiftUIPlacement {
    static func placement(context: WindowPlacementContext) -> WindowPlacement {
        let screens = NSScreen.screens
        guard MacPlacementStrategy.current == .swiftUI, screens.count >= 2 else {
            return WindowPlacement(size: CGSize(width: 960, height: 540))
        }
        // WindowPlacement uses top-left origin coordinates relative to the primary screen.
        let primary = screens[0].frame
        let target = screens[1].visibleFrame
        let position = CGPoint(x: target.minX, y: primary.maxY - target.maxY)
        PrototypeSession.shared.record(
            "mac: SwiftUI placement → position (\(Int(position.x)), \(Int(position.y))) size \(Int(target.width))×\(Int(target.height)); "
                + "default display \(MacPresentationController.describe(context.defaultDisplay.bounds))"
        )
        return WindowPlacement(position, size: target.size)
    }
}

// MARK: Platform hooks

struct PresenterPlatformModifier: ViewModifier {
    let session: PrototypeSession
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .background(WindowBridge { MacPresentationController.shared.attachPresenter($0) })
            .onAppear { MacPresentationController.shared.startObservingScreens() }
            // DOC-04: opening a document shows the presentation window.
            .onChange(of: session.documentGeneration) {
                openWindow(id: PrototypeScene.presentationID)
            }
    }
}

struct PresentationPlatformModifier: ViewModifier {
    let session: PrototypeSession

    func body(content: Content) -> some View {
        content
            .background(WindowBridge { MacPresentationController.shared.attachPresentation($0) })
            .onAppear { MacPresentationController.shared.placeIfNeeded() }
    }
}

struct PlatformDiagnostics: View {
    let session: PrototypeSession
    @AppStorage(MacPlacementStrategy.storageKey) private var strategy = MacPlacementStrategy.appKit
    @AppStorage(MacPrototypeSettings.autoMoveKey) private var autoMove = false
    @AppStorage(MacPrototypeSettings.fullScreenKey) private var enterFullScreen = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            Picker(selection: $strategy) {
                ForEach(MacPlacementStrategy.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Placement")
            }
            Toggle(isOn: $enterFullScreen) { Text(verbatim: "Enter full screen on open") }
            Toggle(isOn: $autoMove) { Text(verbatim: "Auto-move when a screen is added") }
        } header: {
            Text(verbatim: "Settings (apply to the next presentation window)")
        }
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        Text(verbatim: MacPresentationController.describe(screen))
                    }
                    Text(verbatim: MacPresentationController.shared.windowsSummary())
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
            }
            Button { openWindow(id: PrototypeScene.presentationID) } label: {
                Text(verbatim: "Open Presentation Window")
            }
            Button { MacPresentationController.shared.toggleFullScreen() } label: {
                Text(verbatim: "Toggle Full Screen")
            }
            ForEach(Array(NSScreen.screens.indices), id: \.self) { index in
                Button {
                    Task { await MacPresentationController.shared.movePresentation(toScreen: index) }
                } label: {
                    Text(verbatim: "Move Presentation to Screen #\(index)")
                }
            }
            Button {
                session.record("mac: snapshot → \(MacPresentationController.screensSummary()) | \(MacPresentationController.shared.windowsSummary())")
            } label: {
                Text(verbatim: "Log Current State")
            }
        } header: {
            Text(verbatim: "Screens")
        }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
#endif
