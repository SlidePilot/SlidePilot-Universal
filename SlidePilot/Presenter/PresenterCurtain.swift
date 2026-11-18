import SlidePilotCore
import SwiftUI

extension View {
    /// The curtain's toolbar buttons and "Screen is hidden" warning in the presenter
    /// (CUR-01, CUR-02), and the "." key.
    func presenterCurtain(_ session: PresentationSession) -> some View {
        modifier(PresenterCurtainModifier(session: session))
    }

    /// The old app's hidden "." shortcut for the black screen (CUR-01); presentation
    /// clickers send it. A key press instead of a menu item, since SwiftUI cannot hide a
    /// menu item and keep its shortcut. Must wrap `slideNavigationKeys(_:)`, which holds
    /// the keyboard focus.
    func blackCurtainKey(_ session: PresentationSession) -> some View {
        onKeyPress(keys: ["."]) { press in
            // Plain "." only; ⌘. and other combinations stay with the system.
            guard press.modifiers.isEmpty else { return .ignored }
            session.curtain.toggle(.black)
            return .handled
        }
    }
}

private struct PresenterCurtainModifier: ViewModifier {
    let session: PresentationSession

    func body(content: Content) -> some View {
        content
            .toolbar {
                if session.curtain.isShown {
                    ToolbarItem(placement: Self.warningPlacement) {
                        HiddenScreenWarning()
                    }
                    // A status, not a button: no glass capsule around it.
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItemGroup {
                    CurtainToggle(curtain: .black, session: session)
                        .help(Text("Cover the presentation with a black screen"))
                    CurtainToggle(curtain: .white, session: session)
                        .help(Text("Cover the presentation with a white screen"))
                }
            }
            .blackCurtainKey(session)
    }

    #if os(macOS)
    // The center of the title bar.
    private static let warningPlacement = ToolbarItemPlacement.status
    #else
    // The iPad has no status area in its top toolbar; next to the document title.
    private static let warningPlacement = ToolbarItemPlacement.topBarLeading
    #endif
}

/// Tells the presenter that the audience sees a curtain instead of the slide (CUR-02).
/// Replaces the old app's custom warning banner.
private struct HiddenScreenWarning: View {
    var body: some View {
        // Toolbars show labels icon-only on iPad (also with .titleAndIcon); the warning
        // needs its text. Only the icon is orange: orange text is too faint in light mode.
        HStack {
            Image(systemName: "eye.slash")
                .foregroundStyle(.orange)
            Text("Screen is hidden")
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Covers the whole presentation in black or white while a curtain is shown (CUR-01).
/// Part of the slide surface, so the colors are the content, not UI colors.
struct CurtainCover: View {
    let curtain: Curtain

    var body: some View {
        switch curtain {
        case .none:
            EmptyView()
        case .black:
            Color.black
                .accessibilityElement()
                .accessibilityLabel(Text("Screen is hidden"))
        case .white:
            Color.white
                .accessibilityElement()
                .accessibilityLabel(Text("Screen is hidden"))
        }
    }
}
