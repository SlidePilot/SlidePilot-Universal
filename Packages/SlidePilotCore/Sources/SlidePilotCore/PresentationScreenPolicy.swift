/// Where the Mac presentation window goes (DOC-05, changed).
///
/// Screens are given in system order (the first one has the menu bar) and identified by
/// any stable ID, so the rules stay testable without AppKit.
public enum PresentationScreenPolicy {
    /// What to do with a running presentation after the connected screens changed.
    public enum Reaction<ScreenID: Hashable>: Hashable {
        case keep
        /// Close the presentation window and open it again on this screen. A full-screen
        /// window in another Space cannot be moved (see docs/prototypes/external-display.md).
        case reopen(on: ScreenID)
    }

    /// Opening a document starts the presentation only if a second screen is connected.
    public static func startsWhenOpening(screenCount: Int) -> Bool {
        screenCount >= 2
    }

    /// The screen for a new presentation window. Like the old app this is the second screen,
    /// unless the presenter window is on it; then it is the first other screen. With one
    /// screen the presentation shares it (full screen in its own Space).
    public static func screen<ScreenID: Hashable>(in screens: [ScreenID], presenterScreen: ScreenID?) -> ScreenID? {
        guard screens.count >= 2 else { return screens.first }
        if screens[1] != presenterScreen { return screens[1] }
        return screens.first { $0 != presenterScreen }
    }

    /// Reaction to a screen change while presenting.
    ///
    /// - A screen added while the presentation shares the presenter's screen takes over
    ///   the presentation. A presentation that already has its own screen stays there.
    /// - If the presentation's screen was removed, it reopens on a remaining screen.
    public static func reaction<ScreenID: Hashable>(
        previous: [ScreenID],
        current: [ScreenID],
        presentationScreen: ScreenID?,
        presenterScreen: ScreenID?
    ) -> Reaction<ScreenID> {
        guard let presentationScreen else { return .keep }
        guard current.contains(presentationScreen) else {
            return screen(in: current, presenterScreen: presenterScreen).map { .reopen(on: $0) } ?? .keep
        }
        let added = current.filter { !previous.contains($0) && $0 != presenterScreen }
        if presentationScreen == presenterScreen, let newScreen = added.first {
            return .reopen(on: newScreen)
        }
        return .keep
    }

    /// Whether the presenter window should go back to the screen it was on before a screen
    /// change. macOS can move it to a newly connected screen (back to where it was in an
    /// earlier session), so it would end up behind the presentation that took that screen.
    public static func presenterShouldReturn<ScreenID: Hashable>(
        from currentScreen: ScreenID?,
        to previousScreen: ScreenID?,
        presentationScreen: ScreenID?,
        screens: [ScreenID]
    ) -> Bool {
        guard let currentScreen, let previousScreen, currentScreen != previousScreen,
              screens.contains(previousScreen)
        else { return false }
        return currentScreen == presentationScreen
    }
}
