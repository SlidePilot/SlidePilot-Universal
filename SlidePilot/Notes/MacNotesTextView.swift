#if os(macOS)
import AppKit
import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// The notes text view on the Mac (NOTES-04).
///
/// An `NSTextView`, because SwiftUI's `TextEditor` cannot do what the notes need: its
/// `AttributedString` formatting has no lists, no paragraph spacing and no List…/Spacing…
/// panels, and its SwiftUI font attributes cannot be written as RTF, the notes' storage
/// format (NOTES-10). This and `TouchNotesTextView` are the only AppKit/UIKit text views.
struct NotesTextView: NSViewRepresentable {
    let model: NotesModel
    let page: Int
    let actions: NotesTextActions

    private static let containerInset = NSSize(width: 6, height: 8)
    /// Where the first line of text starts, for the empty notes' placeholder: the container
    /// inset plus the default line fragment padding (5 pt).
    static let textInsets = EdgeInsets(top: containerInset.height, leading: containerInset.width + 5, bottom: 0, trailing: containerInset.width + 5)

    func makeCoordinator() -> NotesTextCoordinator {
        NotesTextCoordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusReportingTextView()
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesRuler = true
        textView.isRulerVisible = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.textContainerInset = Self.containerInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(String(localized: "Notes"))
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.onFocusChange = { [model] isFocused in
            if model.isEditing != isFocused {
                model.isEditing = isFocused
            }
        }
        actions.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        textView.isEditable = model.isAvailable
        if coordinator.page != page || coordinator.loadedNotes != model.stored {
            coordinator.load(into: textView, page: page)
        }
        // Text typed on an empty page gets the notes font size (NOTES-05).
        // Only when the size differs, so bold or italic chosen before typing stays.
        let size = model.fontSize(forPage: page)
        if textView.string.isEmpty, (textView.typingAttributes[.font] as? NSFont)?.pointSize != size {
            textView.typingAttributes = NotesTextCoordinator.typingAttributes(size: size)
        }
        // Finishing hands the keyboard to the window's SwiftUI content, where the slide
        // keys are (NAV-01); with no first responder at all they would not arrive.
        if !model.isEditing, let window = textView.window, window.firstResponder === textView {
            window.makeFirstResponder(window.contentView)
        }
    }

    /// Hiding the notes while editing gives the keys back to the slides and clears undo,
    /// like the old app (NOTES-04).
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: NotesTextCoordinator) {
        coordinator.dismantle(scrollView.documentView as? NSTextView)
    }
}

/// Reports when the text view gets or loses the keyboard, for the Done button and the
/// plain-letter shortcuts (NOTES-04), and adds the automatic lists (NOTES-13).
private final class FocusReportingTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        // AppKit gives the keyboard to the window's first key view while the window is
        // being shown, which would be the notes; the slides keep it instead (NAV-01).
        // Clicks, Tab and VoiceOver still reach the notes once the window is on screen.
        guard window?.isVisible == true else { return false }
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onFocusChange?(false)
        }
        return accepted
    }

    // MARK: Automatic lists (NOTES-13)

    /// `* ` or `- ` at the start of a line starts a list. The space is typed first, so
    /// Undo right after the conversion brings back the typed characters.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        guard typed == " ", !hasMarkedText(), let textStorage,
              let edit = NotesList.editAfterTypingSpace(in: textStorage, caret: selectedRange().location)
        else { return }
        apply(edit)
    }

    /// Return on an empty list item ends the list.
    override func insertNewline(_ sender: Any?) {
        if let textStorage, let edit = NotesList.editForReturn(in: textStorage, selection: selectedRange(), typingAttributes: typingAttributes) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    /// Backspace at the start of a list item removes its marker.
    override func deleteBackward(_ sender: Any?) {
        if let textStorage, let edit = NotesList.editForBackspace(in: textStorage, selection: selectedRange(), typingAttributes: typingAttributes) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
    }

    /// Applies a list edit as its own undo step, through the text view's own change
    /// handling (undo, delegate, text storage delegate).
    private func apply(_ edit: NotesList.Edit) {
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement.string) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        typingAttributes = edit.typingAttributes
        breakUndoCoalescing()
    }
}

final class NotesTextCoordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    private let model: NotesModel
    /// The page and notes the text view shows.
    private(set) var page: Int?
    private(set) var loadedNotes: CompanionNotes?
    private var isLoading = false
    /// The notes' own undo history. The window's undo manager belongs to the PDF document:
    /// text edits registered there would mark the PDF edited, and macOS would ask to save
    /// or duplicate the PDF.
    private let undoManager = UndoManager()

    init(model: NotesModel) {
        self.model = model
    }

    static func typingAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.textColor]
    }

    /// Shows the notes of `page`. On the same page (new font size, replaced notes) the
    /// selection stays. Undo is cleared on every load, like on a page change in the old
    /// app: its actions refer to the text that was replaced.
    func load(into textView: NSTextView, page: Int) {
        isLoading = true
        defer { isLoading = false }
        let isSamePage = self.page == page
        let selection = textView.selectedRange()
        let text = NSMutableAttributedString(attributedString: model.text(forPage: page) ?? NSAttributedString())
        text.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: text.length))
        textView.textStorage?.setAttributedString(text)
        let location = isSamePage ? min(selection.location, text.length) : 0
        let length = isSamePage ? min(selection.length, text.length - location) : 0
        textView.setSelectedRange(NSRange(location: location, length: length))
        textView.undoManager?.removeAllActions()
        self.page = page
        loadedNotes = model.stored
    }

    func dismantle(_ textView: NSTextView?) {
        textView?.undoManager?.removeAllActions()
        model.finishEditing()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }

    /// Escape finishes editing, like ⌘↩ and clicking outside (NOTES-04, changed). Handling
    /// it here keeps NSTextView's completion list from opening and stops the key, so no
    /// other Escape action runs. Escape while composing stays with the input method.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText() else { return false }
        model.finishEditing()
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoading, let page, let textView = notification.object as? NSTextView else { return }
        model.setText(textView.attributedString(), forPage: page)
        loadedNotes = model.stored
    }

    /// Notes always use the system text color (NOTES-04): colors from the font panel or
    /// pasted text are replaced before they are drawn.
    /// Nonisolated like the delegate protocol; it touches only its arguments.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedRange.length > 0 else { return }
        textStorage.removeAttribute(.backgroundColor, range: editedRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: editedRange)
    }
}
#endif
