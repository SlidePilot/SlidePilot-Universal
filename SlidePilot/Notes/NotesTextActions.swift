import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension FocusedValues {
    /// The formatting actions of the notes editor while it has the keyboard (NOTES-04).
    @Entry var notesTextActions: NotesTextActions?
}

/// The Format menu's text actions on the notes text view (NOTES-04). They act on the
/// selection like the system's own text formatting and are undoable.
final class NotesTextActions {
    #if os(macOS)
    weak var textView: NSTextView?
    #else
    weak var textView: UITextView?
    #endif

    func toggleBold() {
        #if os(macOS)
        toggle(.boldFontMask)
        #else
        textView?.toggleBoldface(nil)
        #endif
    }

    func toggleItalic() {
        #if os(macOS)
        toggle(.italicFontMask)
        #else
        textView?.toggleItalics(nil)
        #endif
    }

    func toggleUnderline() {
        #if os(macOS)
        textView?.underline(nil)
        #else
        textView?.toggleUnderline(nil)
        #endif
    }

    #if os(macOS)
    func alignLeft() { textView?.alignLeft(nil) }
    func alignCenter() { textView?.alignCenter(nil) }
    func alignRight() { textView?.alignRight(nil) }
    func showListPanel() { textView?.orderFrontListPanel(nil) }
    func showSpacingPanel() { textView?.orderFrontSpacingPanel(nil) }

    /// Adds or removes bold or italic through the font manager, like the standard Format
    /// menu, so the text view applies it to the selection with undo.
    private func toggle(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let selection = textView.selectedRange()
        let font: NSFont? = if selection.length > 0, let storage = textView.textStorage, selection.location < storage.length {
            storage.attribute(.font, at: selection.location, effectiveRange: nil) as? NSFont
        } else {
            textView.typingAttributes[.font] as? NSFont
        }
        // The font manager reads the trait from the sender's tag.
        let sender = NSMenuItem()
        sender.tag = Int(trait.rawValue)
        if let font, manager.traits(of: font).contains(trait) {
            manager.removeFontTrait(sender)
        } else {
            manager.addFontTrait(sender)
        }
    }
    #endif
}
