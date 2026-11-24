import SwiftUI

/// The task the presenter's toolbar is focused on. In compact sizes (a phone, a narrow iPad
/// window) the bar has room for a few items only: while the notes are edited or the presenter
/// draws, the other presenter items move to the overflow menu, so Done and the drawing tools
/// stay in the bar (#152). Regular sizes and the Mac keep every item in place; their bar has
/// room for the drawing tools.
enum PresenterToolbarFocus {
    case none
    case notes
    case drawing

    /// Where an item that is not part of the focused task goes: its usual `placement`, or
    /// the overflow menu while a task is focused.
    func placement(_ placement: ToolbarItemPlacement = .automatic) -> ToolbarItemPlacement {
        self == .none ? placement : .secondaryAction
    }
}

extension EnvironmentValues {
    @Entry var presenterToolbarFocus = PresenterToolbarFocus.none
    /// Whether the presenter draws on iPhone or iPad: the clock and the external display tip
    /// make room for the slide (#152). The Mac keeps them.
    @Entry var presenterMakesRoomForDrawing = false
}

extension View {
    /// Sets the toolbar focus from the session and the size classes. Apply it outside the
    /// navigator's split view: its columns report their own, narrower size classes.
    func presenterToolbarFocus(_ session: PresentationSession) -> some View {
        modifier(PresenterToolbarFocusModifier(session: session))
    }
}

private struct PresenterToolbarFocusModifier: ViewModifier {
    let session: PresentationSession
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.presenterToolbarFocus, focus)
            .environment(\.presenterMakesRoomForDrawing, makesRoomForDrawing)
    }

    private var makesRoomForDrawing: Bool {
        #if os(iOS)
        session.drawing.isActive
        #else
        false
        #endif
    }

    private var focus: PresenterToolbarFocus {
        #if os(iOS)
        guard horizontalSizeClass == .compact || verticalSizeClass == .compact else { return .none }
        if session.drawing.isActive { return .drawing }
        if session.notes.isEditing { return .notes }
        #endif
        return .none
    }
}
