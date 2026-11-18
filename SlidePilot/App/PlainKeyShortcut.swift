import SwiftUI

extension FocusedValues {
    /// `true` while a text field of the focused window has the keyboard, e.g. the
    /// navigator's page field (LAY-06).
    @Entry var isEditingText: Bool?
}

extension View {
    /// A menu shortcut without modifiers (e.g. **O** for the navigator). It is off while a
    /// text field of the focused window has the keyboard, so typing there never fires it
    /// (the old app had no such check).
    func plainKeyShortcut(_ key: KeyEquivalent) -> some View {
        modifier(PlainKeyShortcut(key: key))
    }
}

private struct PlainKeyShortcut: ViewModifier {
    let key: KeyEquivalent
    @FocusedValue(\.isEditingText) private var isEditingText

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(key, modifiers: [])
            .disabled(isEditingText == true)
    }
}
