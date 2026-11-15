/// The page-number field of the slide navigator (LAY-06).
public enum NavigatorPageField {
    /// The zero-based page that typed `text` points at, or `nil` if it is not a number.
    ///
    /// Like the old app, the number is one-based and clamped to the first and last page,
    /// so `0` points at the first page and a number past the end at the last one.
    /// Text search is not part of parity, so other text points at no page.
    public static func page(for text: String, pageCount: Int) -> Int? {
        guard pageCount > 0, let number = Int(text) else { return nil }
        return min(max(number - 1, 0), pageCount - 1)
    }

    /// Whether typing `character` in the thumbnail list moves it into the field.
    /// The old app did this for letters and digits only.
    public static func startsInput(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
