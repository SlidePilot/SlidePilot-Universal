import SlidePilotCore
import SwiftUI

/// Notes Mode and Split Position in the View menu, below Show Notes (NOTES-01, NOTES-02).
/// The old app had them in its Notes menu; Show Notes already moved to the View menu.
/// Off in draw mode (DRAW-05), when the layout commands are off too.
struct NotesModeMenuItems: View {
    @FocusedValue(\.slideNavigation) private var session
    @FocusedValue(\.presenterLayout) private var layout

    var body: some View {
        let session = layout == nil ? nil : session
        NotesModeMenus(session: session)
            .disabled(session == nil)
    }
}

/// The Notes Mode and Split Position submenus, shared by the View menu and the toolbar.
private struct NotesModeMenus: View {
    let session: PresentationSession?

    var body: some View {
        Picker(selection: mode) {
            ForEach(NotesMode.allCases, id: \.self) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        } label: {
            // The subtitle shows the choice without opening the submenu, like the slot pickers.
            Text("Notes Mode")
            Text(mode.wrappedValue.title)
        }
        .pickerStyle(.menu)
        Picker(selection: position) {
            ForEach(Array(NotesPosition.allCases.enumerated()), id: \.element) { index, position in
                Label(position.title, systemImage: position.systemImage)
                    .tag(position)
                    // ⌥⌘0 to ⌥⌘4, in the old menu's order (NOTES-02).
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command, .option])
            }
        } label: {
            Text("Split Position")
            Text(position.wrappedValue.title)
        }
        .pickerStyle(.menu)
    }

    private var mode: Binding<NotesMode> {
        Binding {
            session?.notesDisplay.mode ?? .text
        } set: {
            session?.setNotesMode($0)
        }
    }

    private var position: Binding<NotesPosition> {
        Binding {
            session?.notesDisplay.position ?? .none
        } set: {
            session?.setNotesPosition($0)
        }
    }
}

/// The Notes menu in the presenter's toolbar (NOTES-01, NOTES-02).
private struct NotesModeToolbar: ToolbarContent {
    let session: PresentationSession

    var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                NotesModeMenus(session: session)
            } label: {
                Label("Notes Mode", systemImage: session.notesDisplay.toolbarSystemImage)
            }
            .help(Text("Notes Mode"))
        }
    }
}

extension View {
    /// Adds the Notes menu to the toolbar (hidden in draw mode, DRAW-05) and shows the right
    /// half when the notes slot appears in Split mode without a position (NOTES-02).
    func notesModeControls(_ session: PresentationSession) -> some View {
        toolbar {
            if !session.drawing.isActive {
                NotesModeToolbar(session: session)
            }
        }
        .onChange(of: session.layout.isVisible(.notes)) { _, isVisible in
            if isVisible { session.notesSlotDidShow() }
        }
    }
}

extension NotesMode {
    /// The old app's menu titles.
    var title: LocalizedStringKey {
        switch self {
        case .text: "Text"
        case .split: "Split"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .split: "rectangle.split.2x1"
        }
    }
}

extension NotesPosition {
    /// The old app's menu titles: the half of the page with the notes.
    var title: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .right: "Right"
        case .left: "Left"
        case .bottom: "Bottom"
        case .top: "Top"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "rectangle"
        case .right: "rectangle.righthalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .top: "rectangle.tophalf.inset.filled"
        }
    }
}

private extension NotesDisplay {
    var toolbarSystemImage: String {
        showsSplitNotes ? position.systemImage : "note.text"
    }
}
