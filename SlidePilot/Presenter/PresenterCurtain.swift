import SlidePilotCore
import SwiftUI

extension View {
    /// The old app's hidden "." shortcut for the black screen (CUR-01); presentation
    /// clickers send it. A key press instead of a menu item, since SwiftUI cannot hide a
    /// menu item and keep its shortcut. Must wrap `slideNavigationKeys(_:)`, which holds
    /// the keyboard focus.
    func blackCurtainKey(_ session: PresentationSession) -> some View {
        onKeyPress(keys: ["."]) { press in
            // Plain "." only; ⌘. and other combinations stay with the system.
            // Typed into the notes while they are edited (NOTES-04).
            guard press.modifiers.isEmpty, !session.notes.isEditing else { return .ignored }
            session.curtain.toggle(.black)
            return .handled
        }
    }
}

/// The Curtain button in the presenter's toolbar (CUR-01; product-owner decision
/// 2026-11-25, #189): a click or tap shows the curtain in the color shown last, black until
/// white is chosen, or hides it. Its menu picks black or white.
struct CurtainToolbarMenu: View {
    let session: PresentationSession

    var body: some View {
        let state = session.curtainState
        Menu {
            CurtainToggle(curtain: .black, session: session)
            CurtainToggle(curtain: .white, session: session)
        } label: {
            Label("Curtain", systemImage: state.color.curtainSymbol)
        } primaryAction: {
            session.curtainState.toggle()
        }
        .help(state.helpText)
        // VoiceOver on iOS does not read the help text: the hint says what a tap does.
        .accessibilityHint(state.helpText)
        // The symbol shows the color; the warning next to the title shows that it is on.
        .accessibilityValue(state.accessibilityValue)
    }
}

/// Tells the presenter that the audience sees a curtain instead of the slide (CUR-02).
/// Replaces the old app's custom warning banner.
struct HiddenScreenWarning: View {
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

    #if os(macOS)
    /// The center of the title bar.
    static let placement = ToolbarItemPlacement.status
    #else
    /// The iPad has no status area in its top toolbar; next to the document title.
    static let placement = ToolbarItemPlacement.topBarLeading
    #endif
}

extension Curtain {
    /// The symbol of a curtain color, shared by the presenter and the remote (CUR-01, REM-07).
    var curtainSymbol: String {
        switch self {
        case .none: "rectangle.dashed"
        case .black: "rectangle.fill"
        case .white: "rectangle"
        }
    }
}

extension CurtainState {
    var helpText: Text {
        switch toggled {
        case .none: Text("Show the slides again")
        case .black: Text("Cover the presentation with a black screen")
        case .white: Text("Cover the presentation with a white screen")
        }
    }

    var accessibilityValue: Text {
        switch shown {
        case .none: Text("Off")
        case .black: Text("Black Screen")
        case .white: Text("White Screen")
        }
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
