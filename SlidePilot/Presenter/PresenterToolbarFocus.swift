import SwiftUI

/// How much room the presenter's toolbar has and which task it is focused on. In compact
/// sizes (a phone, a narrow iPad window) the bar has room for a few items only: the less
/// important items (Go Back, Layout, Pointer, the external display status) live in the
/// overflow menu, and while the notes are edited or the presenter draws, every other item
/// moves there too, so Done and the drawing tools stay in the bar (#152, #189). A regular
/// iPad window in portrait moves only Go Back away from the title, so the title keeps its
/// room (#207).
/// Regular sizes in landscape and the Mac keep every item in place.
enum PresenterToolbarFocus {
    /// Regular size: every item in the bar.
    case none
    /// Regular size in a window taller than wide (iPad portrait): Go Back among the secondary
    /// actions, which a wide bar shows inline after the title and a narrow one in the
    /// overflow menu.
    case portrait
    /// Compact size without a focused task: the less important items in the overflow menu.
    case compact
    case notes
    case drawing

    /// How readily an item leaves a bar that is short of room.
    enum Priority {
        /// Time, Curtain and Draw: in the bar unless a task is focused.
        case high
        /// Leaves a compact bar.
        case low
        /// Also leaves a regular bar in portrait.
        case lowest
    }

    /// Where an item that is not part of the focused task goes: its usual `placement`, or
    /// the overflow menu while a task is focused or while the bar is short of room for an
    /// item of this priority.
    func placement(_ placement: ToolbarItemPlacement = .automatic, priority: Priority = .high) -> ToolbarItemPlacement {
        isInBar(priority: priority) ? placement : .secondaryAction
    }

    /// Whether an item keeps its own place in the bar, so a group separator next to it makes
    /// sense.
    func isInBar(priority: Priority = .high) -> Bool {
        switch self {
        case .none: true
        case .portrait: priority != .lowest
        case .compact: priority == .high
        case .notes, .drawing: false
        }
    }

    /// Whether the bar is compact: the drawing tools and Time take their compact forms.
    var isCompact: Bool {
        switch self {
        case .none, .portrait: false
        case .compact, .notes, .drawing: true
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
    /// Sets the toolbar focus from the session, the size classes and, on iPad, the window's
    /// orientation. Apply it outside the navigator's split view: its columns report their
    /// own, narrower size classes.
    func presenterToolbarFocus(_ session: PresentationSession) -> some View {
        modifier(PresenterToolbarFocusModifier(session: session))
    }
}

private struct PresenterToolbarFocusModifier: ViewModifier {
    let session: PresentationSession
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isPortrait = false
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.presenterToolbarFocus, focus)
            .environment(\.presenterMakesRoomForDrawing, makesRoomForDrawing)
            #if os(iOS)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.size.height > geometry.size.width
            } action: { isPortrait = $0 }
            #endif
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
        guard horizontalSizeClass == .compact || verticalSizeClass == .compact else {
            return isPortrait ? .portrait : .none
        }
        if session.drawing.isActive { return .drawing }
        if session.notes.isEditing { return .notes }
        return .compact
        #else
        return .none
        #endif
    }
}
