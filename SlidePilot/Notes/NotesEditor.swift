import SwiftUI

/// The text notes of the current slide in the presenter's notes slot (NOTES-04).
struct NotesEditor: View {
    let session: PresentationSession
    @State private var actions = NotesTextActions()

    private var notes: NotesModel { session.notes }

    var body: some View {
        if notes.isUnreadable {
            ContentUnavailableView(
                "Notes Can’t Be Shown",
                systemImage: "exclamationmark.triangle",
                description: Text("These notes were saved by a newer version of SlidePilot.")
            )
        } else {
            NotesTextView(model: notes, page: session.currentPage, actions: actions)
                .clipShape(.rect(cornerRadius: 8))
                #if os(macOS)
                // The Mac text background matches the window's, so the area needs an edge.
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator)
                }
                #endif
                .focusedSceneValue(\.notesTextActions, notes.isEditing ? actions : nil)
                // The plain-letter shortcuts are off while typing notes.
                .focusedSceneValue(\.isEditingText, notes.isEditing ? true : nil)
        }
    }
}

extension View {
    /// A click or tap on the empty parts of the slides column (around the slides, on the
    /// clock) finishes editing the notes (NOTES-04). Only while editing, so a click still
    /// gives the keyboard to the slides otherwise.
    func finishesNotesEditingOnTap(_ notes: NotesModel) -> some View {
        background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { notes.finishEditing() }
                .allowsHitTesting(notes.isEditing)
        }
    }

    /// The Done button while the notes are edited; ⌘↩ finishes editing too (NOTES-04).
    func notesEditingControls(_ notes: NotesModel) -> some View {
        toolbar {
            if notes.isEditing {
                // Its own trailing group, apart from the curtain buttons.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        notes.finishEditing()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(Text("Finish editing the notes"))
                }
            }
        }
    }
}

/// Format ▸ Font and Format ▸ Text, with the old app's items and shortcuts (NOTES-04,
/// NOTES-05). On iPad, alignment, lists and spacing are in the text view's formatting panel.
struct NotesFormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            NotesFormatMenuItems()
        }
    }
}

private struct NotesFormatMenuItems: View {
    @FocusedValue(\.notesTextActions) private var actions
    @FocusedValue(\.slideNavigation) private var session

    var body: some View {
        Menu("Font") {
            Button("Bold") { actions?.toggleBold() }
                .keyboardShortcut("b")
                .disabled(actions == nil)
            Button("Italic") { actions?.toggleItalic() }
                .keyboardShortcut("i")
                .disabled(actions == nil)
            Button("Underline") { actions?.toggleUnderline() }
                .keyboardShortcut("u")
                .disabled(actions == nil)
            Divider()
            // All pages of the document, also while not editing (NOTES-05).
            Button("Bigger") { changeFontSize(by: 1) }
                .keyboardShortcut("+")
                .disabled(session?.notes.isAvailable != true)
            Button("Smaller") { changeFontSize(by: -1) }
                .keyboardShortcut("-")
                .disabled(session?.notes.isAvailable != true)
        }
        #if os(macOS)
        Menu("Text") {
            Button("Align Left") { actions?.alignLeft() }
                .keyboardShortcut("{")
            Button("Center") { actions?.alignCenter() }
                .keyboardShortcut("|")
            Button("Align Right") { actions?.alignRight() }
                .keyboardShortcut("}")
            Divider()
            Button("List…") { actions?.showListPanel() }
                .keyboardShortcut("l")
            Button("Spacing…") { actions?.showSpacingPanel() }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
        .disabled(actions == nil)
        #endif
    }

    private func changeFontSize(by delta: CGFloat) {
        guard let session else { return }
        session.notes.changeFontSize(by: delta, onPage: session.currentPage)
    }
}
