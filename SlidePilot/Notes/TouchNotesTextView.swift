#if os(iOS)
import SlidePilotCore
import SlidePilotRendering
import SwiftUI
import UIKit

/// The notes text view on iPad (NOTES-04).
///
/// A `UITextView`, because SwiftUI's `TextEditor` cannot do what the notes need: its
/// `AttributedString` formatting has no lists and no paragraph spacing, and its SwiftUI
/// font attributes cannot be written as RTF, the notes' storage format (NOTES-10). The
/// text view brings the system's text formatting panel (alignment, lists, styles) through
/// its edit menu. This and the Mac's `NotesTextView` are the only AppKit/UIKit text views.
struct NotesTextView: UIViewRepresentable {
    let model: NotesModel
    let page: Int
    let actions: NotesTextActions

    func makeCoordinator() -> NotesTextCoordinator {
        NotesTextCoordinator(model: model)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = NotesUITextView()
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .secondarySystemBackground
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.keyboardDismissMode = .interactive
        textView.accessibilityLabel = String(localized: "Notes")
        textView.delegate = context.coordinator
        textView.textStorage.delegate = context.coordinator
        actions.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        textView.isEditable = model.isAvailable
        if coordinator.page != page || coordinator.loadedNotes != model.stored {
            coordinator.load(into: textView, page: page)
        }
        // Text typed on an empty page gets the notes font size (NOTES-05).
        // Only when the size differs, so bold or italic chosen before typing stays.
        let size = model.fontSize(forPage: page)
        if textView.text.isEmpty, (textView.typingAttributes[.font] as? UIFont)?.pointSize != size {
            textView.typingAttributes = NotesTextCoordinator.typingAttributes(size: size)
        }
        if !model.isEditing, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    /// Hiding the notes while editing ends editing and clears undo, like the old app (NOTES-04).
    static func dismantleUIView(_ textView: UITextView, coordinator: NotesTextCoordinator) {
        textView.undoManager?.removeAllActions()
        coordinator.dismantle()
    }
}

/// A text view with its own undo history and the automatic lists (NOTES-13). The
/// responder chain's undo manager belongs to the PDF document: text edits registered
/// there would mark the PDF edited.
private final class NotesUITextView: UITextView {
    private let notesUndoManager = UndoManager()

    override var undoManager: UndoManager? { notesUndoManager }

    /// `* ` or `- ` at the start of a line starts a list; Return on an empty list item
    /// ends it. The space is typed first, so Undo right after the conversion brings back
    /// the typed characters.
    override func insertText(_ text: String) {
        if text == "\n", let edit = NotesList.editForReturn(in: textStorage, selection: selectedRange, typingAttributes: typingAttributes) {
            apply(edit)
            return
        }
        super.insertText(text)
        if text == " ", markedTextRange == nil, let edit = NotesList.editAfterTypingSpace(in: textStorage, caret: selectedRange.location) {
            apply(edit)
        }
    }

    /// Backspace at the start of a list item removes its marker.
    override func deleteBackward() {
        if let edit = NotesList.editForBackspace(in: textStorage, selection: selectedRange, typingAttributes: typingAttributes) {
            apply(edit)
        } else {
            super.deleteBackward()
        }
    }

    /// Applies a list edit as its own undo step. UITextView has no public way to make a
    /// paragraph style change undoable, so the inverse edit is registered here.
    private func apply(_ edit: NotesList.Edit) {
        let inverse = edit.inverse(in: textStorage, selection: selectedRange, typingAttributes: typingAttributes)
        notesUndoManager.registerUndo(withTarget: self) { textView in
            textView.apply(inverse)
        }
        textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        selectedRange = edit.selection
        typingAttributes = edit.typingAttributes
        delegate?.textViewDidChange?(self)
    }
}

final class NotesTextCoordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
    private let model: NotesModel
    /// The page and notes the text view shows.
    private(set) var page: Int?
    private(set) var loadedNotes: CompanionNotes?
    private var isLoading = false

    init(model: NotesModel) {
        self.model = model
    }

    static func typingAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.label]
    }

    /// Shows the notes of `page`. On the same page (new font size, replaced notes) the
    /// selection stays. Undo is cleared on every load, like on a page change in the old
    /// app: its actions refer to the text that was replaced.
    func load(into textView: UITextView, page: Int) {
        isLoading = true
        defer { isLoading = false }
        let isSamePage = self.page == page
        let selection = textView.selectedRange
        let text = NSMutableAttributedString(attributedString: model.text(forPage: page) ?? NSAttributedString())
        text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length))
        textView.attributedText = text
        let location = isSamePage ? min(selection.location, text.length) : 0
        let length = isSamePage ? min(selection.length, text.length - location) : 0
        textView.selectedRange = NSRange(location: location, length: length)
        textView.undoManager?.removeAllActions()
        self.page = page
        loadedNotes = model.stored
    }

    func dismantle() {
        model.finishEditing()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if !model.isEditing {
            model.isEditing = true
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if model.isEditing {
            model.isEditing = false
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isLoading, let page else { return }
        model.setText(textView.attributedText, forPage: page)
        loadedNotes = model.stored
    }

    /// Notes always use the system text color (NOTES-04): colors from the formatting panel
    /// or pasted text are replaced before they are drawn.
    /// Nonisolated like the delegate protocol; it touches only its arguments.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedRange.length > 0 else { return }
        textStorage.removeAttribute(.backgroundColor, range: editedRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: editedRange)
    }
}
#endif
