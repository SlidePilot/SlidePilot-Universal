import SwiftUI

extension FocusedValues {
    /// The session of the focused presenter or presentation window, for the navigation commands.
    @Entry var slideNavigation: PresentationSession?
}

/// Previous Slide, Next Slide and Go Back in the Presentation menu (NAV-02, NAV-03).
/// The old app had hidden ⌃⌘←/→ items; SwiftUI cannot hide a menu item and keep its
/// shortcut, so they are visible. Plain arrows stay out of the menu: as key equivalents
/// they would win over text fields such as the notes editor.
struct SlideNavigationMenuItems: View {
    @FocusedValue(\.slideNavigation) private var session

    var body: some View {
        Button("Previous Slide") { session?.showPreviousPage() }
            .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
            .disabled(session == nil)
        Button("Next Slide") { session?.nextSlideCommand() }
            .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
            .disabled(session == nil)
        Button("Go Back") { session?.goBack() }
            .keyboardShortcut("g", modifiers: .control)
            .disabled(session?.canGoBack != true)
    }
}

extension PresentationSession {
    /// "Next slide" from the keyboard or the menu, the only entry point that may start the
    /// timer on the first use (NAV-09, TIME-05). Swipes, VoiceOver, links and the remote
    /// call `showNextPage()` directly.
    func nextSlideCommand() {
        showNextPage()
        timer.nextSlideCommandWasUsed()
    }
}

extension View {
    /// Slide change with the keys of NAV-01 in a presenter or presentation window, and the
    /// session for the menu commands.
    func slideNavigationKeys(_ session: PresentationSession) -> some View {
        modifier(SlideNavigationKeys(session: session))
    }

    /// The presenter's Go Back toolbar button (NAV-03) and, on iPad, swipes to change slides (NAV-01).
    func presenterNavigation(_ session: PresentationSession) -> some View {
        modifier(PresenterNavigation(session: session))
    }
}

/// Next: → ↓ PageDown. Previous: ← ↑ PageUp. Presentation clickers send these keys.
/// Space and Return are deliberately not handled, like in the old app (NAV-01).
private struct SlideNavigationKeys: ViewModifier {
    let session: PresentationSession
    @FocusState private var hasKeyboardFocus: Bool

    private static let previousKeys: Set<KeyEquivalent> = [.leftArrow, .upArrow, .pageUp]
    private static let nextKeys: Set<KeyEquivalent> = [.rightArrow, .downArrow, .pageDown]

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.slideNavigation, session)
            // Takes the keyboard when the window opens. A focused text field (e.g. notes)
            // keeps its own arrow keys, since only unhandled presses reach this view.
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear { hasKeyboardFocus = true }
            .onKeyPress(keys: Self.previousKeys) { _ in
                session.showPreviousPage()
                return .handled
            }
            .onKeyPress(keys: Self.nextKeys) { _ in
                session.nextSlideCommand()
                return .handled
            }
    }
}

private struct PresenterNavigation: ViewModifier {
    let session: PresentationSession

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Go Back", systemImage: "arrow.uturn.backward.circle") {
                        session.goBack()
                    }
                    .help(Text("Go back to the previously viewed slide"))
                    .disabled(!session.canGoBack)
                }
            }
            #if os(iOS)
            .contentShape(.rect)
            .gesture(swipe)
            #endif
    }

    #if os(iOS)
    /// A horizontal swipe changes the slide like turning a page: left shows the next slide.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let distance = value.translation
                guard abs(distance.width) > abs(distance.height) else { return }
                if distance.width < 0 {
                    session.showNextPage()
                } else {
                    session.showPreviousPage()
                }
            }
    }
    #endif
}
