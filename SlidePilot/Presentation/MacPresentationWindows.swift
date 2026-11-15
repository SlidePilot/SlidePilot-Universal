#if os(macOS)
import AppKit
import SlidePilotCore
import SwiftUI

/// Scene ID of the presentation windows; each window shows the session with the ID it opens with.
enum PresentationScene {
    static let id = "presentation"
}

/// AppKit glue for the presentation windows (DOC-04, DOC-05, DOC-06). SwiftUI on macOS 26
/// cannot choose a screen, enter full screen or keep another window key, see
/// docs/prototypes/external-display.md. All of that stays in this file.
@MainActor
@Observable
final class MacPresentationWindows {
    private struct Entry {
        weak var presenter: NSWindow?
        weak var presentation: NSWindow?
        /// The screen the presentation was opened on or last seen on.
        var screen: CGDirectDisplayID?
        var isPresenting = false
    }

    @ObservationIgnored private var entries: [PresentationSession.ID: Entry] = [:]
    /// Consumed by the placement of the next presentation window.
    @ObservationIgnored private var nextScreen: CGDirectDisplayID?

    func isPresenting(_ id: PresentationSession.ID) -> Bool {
        entries[id]?.isPresenting == true
    }

    /// Returns `true` when the document window is seen for the first time.
    func attachPresenter(_ window: NSWindow, for id: PresentationSession.ID) -> Bool {
        let isNew = entries[id]?.presenter == nil
        entries[id, default: Entry()].presenter = window
        return isNew
    }

    func presenterDidClose(_ id: PresentationSession.ID) {
        entries[id] = nil
    }

    /// Brings a running presentation to the front and keeps the presenter key.
    /// Returns `false` when no presentation window is open.
    func showRunningPresentation(_ id: PresentationSession.ID) -> Bool {
        guard let entry = entries[id], entry.isPresenting, let window = entry.presentation else { return false }
        window.orderFront(nil)
        entry.presenter?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Chooses the screen for the presentation window that opens next.
    func prepareToOpen(_ id: PresentationSession.ID, on screen: CGDirectDisplayID? = nil) {
        let screens = NSScreen.screens.compactMap(\.displayID)
        let presenterScreen = entries[id]?.presenter?.screen?.displayID
        nextScreen = screen ?? PresentationScreenPolicy.screen(in: screens, presenterScreen: presenterScreen)
        entries[id, default: Entry()].screen = nextScreen
    }

    /// Opens the presentation window directly on the chosen screen, so it never shows up
    /// on the presenter's screen first. `WindowPlacement` uses top-left coordinates
    /// relative to the screen with the menu bar.
    func placement() -> WindowPlacement {
        defer { nextScreen = nil }
        let screens = NSScreen.screens
        guard let primary = screens.first,
              let target = screens.first(where: { $0.displayID == nextScreen }) ?? screens.first
        else { return WindowPlacement() }
        let frame = target.visibleFrame
        let position = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
        return WindowPlacement(position, size: frame.size)
    }

    /// Enters full screen and gives the keyboard back to the presenter (DOC-05, DOC-06).
    func attachPresentation(_ window: NSWindow, for id: PresentationSession.ID) {
        guard entries[id]?.presentation !== window else { return }
        entries[id, default: Entry()].presentation = window
        entries[id, default: Entry()].isPresenting = true
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        Task {
            // Full screen is ignored while SwiftUI is still setting up the new window.
            try? await Task.sleep(for: .milliseconds(150))
            guard self.entries[id]?.presentation === window else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            self.entries[id]?.presenter?.makeKeyAndOrderFront(nil)
        }
    }

    func presentationDidClose(_ id: PresentationSession.ID) {
        entries[id]?.presentation = nil
        entries[id]?.isPresenting = false
    }

    /// Closes the presentation window and waits until SwiftUI has removed it, so the same
    /// session can open a new one.
    func closePresentation(_ id: PresentationSession.ID) async {
        entries[id]?.presentation?.close()
        for _ in 0..<40 where isPresenting(id) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Decides how a running presentation reacts to a screen change.
    func reaction(
        for id: PresentationSession.ID,
        previous: [CGDirectDisplayID],
        current: [CGDirectDisplayID]
    ) -> PresentationScreenPolicy.Reaction<CGDirectDisplayID> {
        guard let entry = entries[id], entry.isPresenting else { return .keep }
        let reaction = PresentationScreenPolicy.reaction(
            previous: previous,
            current: current,
            presentationScreen: entry.screen,
            presenterScreen: entry.presenter?.screen?.displayID
        )
        if reaction == .keep, let screen = entry.presentation?.screen?.displayID {
            // macOS may have moved the window itself; remember where it is now.
            entries[id]?.screen = screen
        }
        return reaction
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

// MARK: - Scene content

/// Content of a presentation window. Closes itself when its document closes.
struct PresentationWindowContent: View {
    let id: PresentationSession.ID?
    @Environment(SessionRegistry.self) private var registry
    @Environment(MacPresentationWindows.self) private var windows
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let id, let session = registry.session(for: id) {
            PresentationView(session: session)
                .background(WindowBridge { windows.attachPresentation($0, for: id) })
                .onDisappear { windows.presentationDidClose(id) }
        } else {
            Color.black
                .onAppear { dismissWindow(id: PresentationScene.id, value: id) }
        }
    }
}

/// The presenter window's part of DOC-04/05: registers the window, starts the presentation
/// on a second screen when the document opens, and follows screen changes while presenting.
private struct PresenterWindowModifier: ViewModifier {
    let session: PresentationSession
    @Environment(MacPresentationWindows.self) private var windows
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .background(WindowBridge { window in
                if windows.attachPresenter(window, for: session.id),
                   PresentationScreenPolicy.startsWhenOpening(screenCount: NSScreen.screens.count)
                {
                    startPresentation()
                }
            })
            .onDisappear { windows.presenterDidClose(session.id) }
            .focusedSceneValue(\.startPresentation, StartPresentationAction(perform: startPresentation))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Presentation", systemImage: "play.rectangle", action: startPresentation)
                        .help(Text("Show the presentation in full screen"))
                }
            }
            .task(id: session.id) { await followScreenChanges() }
    }

    private func startPresentation() {
        guard !windows.showRunningPresentation(session.id) else { return }
        windows.prepareToOpen(session.id)
        openWindow(id: PresentationScene.id, value: session.id)
    }

    private func followScreenChanges() async {
        var previous = NSScreen.screens.compactMap(\.displayID)
        let changes = NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification)
        for await _ in changes {
            // Changes come in bursts, and AppKit moves windows after the notification.
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            let current = NSScreen.screens.compactMap(\.displayID)
            defer { previous = current }
            guard case .reopen(let screen) = windows.reaction(for: session.id, previous: previous, current: current)
            else { continue }
            // A full-screen window in another Space cannot be moved: open a new one there.
            await windows.closePresentation(session.id)
            windows.prepareToOpen(session.id, on: screen)
            openWindow(id: PresentationScene.id, value: session.id)
        }
    }
}

extension View {
    func presenterWindow(for session: PresentationSession) -> some View {
        modifier(PresenterWindowModifier(session: session))
    }
}

/// Hands the hosting `NSWindow` to a closure once the view is in a window.
private struct WindowBridge: NSViewRepresentable {
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
#endif
