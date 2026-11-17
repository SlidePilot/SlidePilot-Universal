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
        /// Where the presenter was before the last screen change, so it can be put back.
        var presenterFrame: CGRect?
        var presenterScreen: CGDirectDisplayID?
        /// The frame of `presenterScreen` at that time, to convert `presenterFrame`.
        var presenterScreenFrame: CGRect?
        /// The connected screens at that time: moves after a screen change are macOS's, not the user's.
        var screensAtPresenterPlace: [CGDirectDisplayID] = []
        var presenterMoves: Task<Void, Never>?
    }

    @ObservationIgnored private var entries: [PresentationSession.ID: Entry] = [:]
    /// Screens for the presentation windows about to open, consumed in order by their
    /// placement (several documents can open at once).
    @ObservationIgnored private var pendingScreens: [CGDirectDisplayID?] = []

    func isPresenting(_ id: PresentationSession.ID) -> Bool {
        entries[id]?.isPresenting == true
    }

    /// Returns `true` when the document window is seen for the first time.
    func attachPresenter(_ window: NSWindow, for id: PresentationSession.ID) -> Bool {
        let isNew = entries[id]?.presenter == nil
        entries[id, default: Entry()].presenter = window
        if isNew {
            // Ends with the entry in presenterDidClose.
            let moves = NotificationCenter.default.notifications(named: NSWindow.didMoveNotification, object: window)
            entries[id]?.presenterMoves = Task { [weak self] in
                for await _ in moves {
                    self?.presenterDidMove(id)
                }
            }
        }
        return isNew
    }

    /// Closing the document ends its presentation (DOC-04).
    func presenterDidClose(_ id: PresentationSession.ID) {
        let presentation = entries[id]?.presentation
        entries[id]?.presenterMoves?.cancel()
        entries[id] = nil
        presentation?.close()
    }

    /// Brings a running presentation to the front and keeps the presenter key.
    /// Returns `false` when no presentation window is open.
    func showRunningPresentation(_ id: PresentationSession.ID) -> Bool {
        guard let entry = entries[id], entry.isPresenting, let window = entry.presentation else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFront(nil)
        entry.presenter?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Remembers where the presenter window is now.
    func rememberPresenterPlace(_ id: PresentationSession.ID) {
        guard let presenter = entries[id]?.presenter else { return }
        entries[id]?.presenterFrame = presenter.frame
        entries[id]?.presenterScreen = presenter.screen?.displayID
        entries[id]?.presenterScreenFrame = presenter.screen?.frame
        entries[id]?.screensAtPresenterPlace = NSScreen.screens.compactMap(\.displayID)
    }

    /// A move by the user while presenting becomes the place to return to.
    private func presenterDidMove(_ id: PresentationSession.ID) {
        guard let entry = entries[id], entry.isPresenting,
              entry.screensAtPresenterPlace == NSScreen.screens.compactMap(\.displayID)
        else { return }
        rememberPresenterPlace(id)
    }

    /// Puts the presenter window back if macOS moved it onto the presentation's screen
    /// during a screen change (hardware test M3).
    func keepPresenterInPlace(_ id: PresentationSession.ID) {
        guard let entry = entries[id], let presenter = entry.presenter, let frame = entry.presenterFrame,
              let oldScreenFrame = entry.presenterScreenFrame,
              let screen = NSScreen.screens.first(where: { $0.displayID == entry.presenterScreen })
        else { return }
        let screens = NSScreen.screens.compactMap(\.displayID)
        let current = presenter.screen?.displayID
        guard PresentationScreenPolicy.presenterShouldReturn(
            from: current,
            to: entry.presenterScreen,
            presentationScreen: entry.screen,
            screens: screens
        ) else { return }
        let restored = PresentationScreenPolicy.frame(frame, savedOn: oldScreenFrame, screenNowAt: screen.frame)
        // The screen may have a smaller resolution now.
        presenter.setFrame(presenter.constrainFrameRect(restored, to: screen), display: true)
        presenter.makeKeyAndOrderFront(nil)
    }

    /// Chooses the screen for the presentation window that opens next.
    func prepareToOpen(_ id: PresentationSession.ID, on screen: CGDirectDisplayID? = nil) {
        let screens = NSScreen.screens.compactMap(\.displayID)
        let presenterScreen = entries[id]?.presenter?.screen?.displayID
        let target = screen ?? PresentationScreenPolicy.screen(in: screens, presenterScreen: presenterScreen)
        pendingScreens.append(target)
        entries[id, default: Entry()].screen = target
    }

    /// Opens the presentation window directly on the chosen screen, so it never shows up
    /// on the presenter's screen first. `WindowPlacement` uses top-left coordinates
    /// relative to the screen with the menu bar.
    func placement() -> WindowPlacement {
        let next = pendingScreens.isEmpty ? nil : pendingScreens.removeFirst()
        let screens = NSScreen.screens
        guard let primary = screens.first,
              let target = screens.first(where: { $0.displayID == next }) ?? screens.first
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
        // Deliberately unowned and short-lived: it only finishes setting up this window and
        // checks that the window is still the session's presentation before touching it.
        Task {
            // Full screen is ignored while SwiftUI is still setting up the new window.
            try? await Task.sleep(for: .milliseconds(150))
            guard let entry = self.entries[id], entry.presentation === window else { return }
            // Safety net if the placement went to another screen than chosen.
            if !window.styleMask.contains(.fullScreen), let screen = entry.screen,
               window.screen?.displayID != screen,
               let target = NSScreen.screens.first(where: { $0.displayID == screen })
            {
                window.setFrame(target.visibleFrame, display: true)
            }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            self.entries[id]?.presenter?.makeKeyAndOrderFront(nil)
        }
    }

    /// Ignores a late call from a window that was already replaced by a new one.
    func presentationDidClose(_ id: PresentationSession.ID, window: NSWindow?) {
        guard let entry = entries[id], window == nil || entry.presentation === window else { return }
        entries[id]?.presentation = nil
        entries[id]?.isPresenting = false
    }

    /// Closes the presentation window and waits until SwiftUI has removed it, so the same
    /// session can open a new one. Returns `false` if the waiting task was cancelled.
    func closePresentation(_ id: PresentationSession.ID) async -> Bool {
        entries[id]?.presentation?.close()
        for _ in 0..<40 where isPresenting(id) {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    /// Decides how a running presentation reacts to a screen change.
    func reaction(
        for id: PresentationSession.ID,
        previous: [CGDirectDisplayID],
        current: [CGDirectDisplayID]
    ) -> PresentationScreenPolicy.Reaction<CGDirectDisplayID> {
        guard let entry = entries[id], entry.isPresenting else { return .keep }
        // The presenter's screen from before the change: macOS may already have moved it.
        let presenterScreen = entry.presenterScreen ?? entry.presenter?.screen?.displayID
        let reaction = PresentationScreenPolicy.reaction(
            previous: previous,
            current: current,
            presentationScreen: entry.screen,
            presenterScreen: presenterScreen
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
    @Environment(\.dismiss) private var dismiss
    @State private var window: NSWindow?

    var body: some View {
        if let id, let session = registry.session(for: id) {
            PresentationView(session: session)
                .background(WindowBridge { newWindow in
                    window = newWindow
                    windows.attachPresentation(newWindow, for: id)
                })
                .onDisappear { windows.presentationDidClose(id, window: window) }
                // After a click into the presentation, ⌥⌘P still works and hands the
                // keyboard back to the presenter.
                .focusedSceneValue(\.startPresentation, StartPresentationAction {
                    _ = windows.showRunningPresentation(id)
                })
                // Like the old app, A, P and N also work while the presentation is key (LAY-02).
                .focusedSceneValue(\.presenterLayout, session.layout)
                // Start/Stop, Reset and Mode also work after a click into the presentation.
                .focusedSceneValue(\.presenterTimer, FocusedPresenterTimer(session: session, showSetTimer: nil))
        } else {
            // Fallback if the document went away first: close this window. The window
            // itself, not by value, since the scene's value is non-optional.
            Color.black
                .onAppear { dismiss() }
        }
    }
}

/// The presenter window's part of DOC-04/05: registers the window, starts the presentation
/// on a second screen when the document opens, and follows screen changes while presenting.
private struct PresenterWindowModifier: ViewModifier {
    let session: PresentationSession
    @Environment(MacPresentationWindows.self) private var windows
    @Environment(SessionRegistry.self) private var registry
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .background(WindowBridge { window in
                // The presentation window looks the session up, so register it first.
                registry.register(session)
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
        windows.rememberPresenterPlace(session.id)
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
            // Later notifications of the same burst find nothing new.
            guard current != previous else { continue }
            defer { previous = current }
            if case .reopen(let screen) = windows.reaction(for: session.id, previous: previous, current: current) {
                // A full-screen window in another Space cannot be moved: open a new one there.
                guard await windows.closePresentation(session.id) else { return }
                windows.prepareToOpen(session.id, on: screen)
                openWindow(id: PresentationScene.id, value: session.id)
                // macOS may move the presenter while the new window enters full screen.
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            guard windows.isPresenting(session.id) else { continue }
            windows.keepPresenterInPlace(session.id)
            windows.rememberPresenterPlace(session.id)
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
