import SwiftUI

/// How much room the presenter's toolbar has and which task it is focused on. In compact
/// sizes (a phone, a narrow iPad window) the bar has room for a few items only: the less
/// important items (Go Back, Layout, Pointer, the external display status) live in the
/// overflow menu, and while the notes are edited or the presenter draws, every other item
/// moves there too, so Done and the drawing tools stay in the bar (#152, #189). Regular sizes
/// and the Mac keep every item in place.
enum PresenterToolbarFocus {
    /// Regular size: every item in the bar.
    case none
    /// Compact size without a focused task: the less important items in the overflow menu.
    case compact
    case notes
    case drawing

    /// Where an item that is not part of the focused task goes: its usual `placement`, or
    /// the overflow menu while a task is focused or, for a less important item, while the
    /// bar is compact.
    func placement(_ placement: ToolbarItemPlacement = .automatic, isLessImportant: Bool = false) -> ToolbarItemPlacement {
        switch self {
        case .none: placement
        case .compact: isLessImportant ? .secondaryAction : placement
        case .notes, .drawing: .secondaryAction
        }
    }

    /// Whether an item keeps its own place in the bar, so a group separator next to it makes
    /// sense.
    func isInBar(isLessImportant: Bool = false) -> Bool {
        switch self {
        case .none: true
        case .compact: !isLessImportant
        case .notes, .drawing: false
        }
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
        return .compact
        #else
        return .none
        #endif
    }
}
