import Foundation

/// The page-number field of the slide navigator (LAY-06).
///
/// A typed number highlights that page; Return jumps to it. Like the old app, a number
/// past either end highlights the first or last page, and anything else (letters, an
/// empty field) highlights nothing. Text search is not part of parity.
public enum NavigatorPageField {
    /// The zero-based page that `text` points to, or `nil` if it is not a number.
    public static func page(for text: String, pageCount: Int) -> Int? {
        guard pageCount > 0,
              let number = Int(text.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return min(max(number - 1, 0), pageCount - 1)
    }

    /// Whether a key typed in the thumbnail list moves to the page field: letters and
    /// digits do, like in the old app.
    public static func startsInput(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
