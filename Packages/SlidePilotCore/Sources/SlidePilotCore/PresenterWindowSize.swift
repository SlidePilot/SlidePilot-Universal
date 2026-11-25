import CoreGraphics

/// Size of a newly opened presenter window on the Mac (DOC-04).
///
/// A new window opens at 1400 × 900 pt, so the slides, notes and clock have room from the
/// start. On a smaller screen it takes the whole visible area instead. Windows the system
/// restores keep their frame.
public enum PresenterWindowSize {
    /// The size of a new presenter window when the screen has room for it.
    public static let preferred = CGSize(width: 1400, height: 900)

    /// The size of a new presenter window on a screen with this visible size. Without a
    /// known screen (an empty size) it is the preferred size.
    public static func size(forVisibleScreen visible: CGSize) -> CGSize {
        guard visible.width > 0, visible.height > 0 else { return preferred }
        return CGSize(width: min(preferred.width, visible.width.rounded(.down)),
                      height: min(preferred.height, visible.height.rounded(.down)))
    }
}
