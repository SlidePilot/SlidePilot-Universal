import CoreGraphics

/// Size of a newly opened presenter window on the Mac (DOC-04).
///
/// A new window fills about 85 % of the screen's visible area, centered, so the slides,
/// notes and clock have room from the start. Windows the system restores keep their frame.
public enum PresenterWindowSize {
    /// Share of the visible screen width and height a new presenter window takes.
    public static let screenFraction: CGFloat = 0.85

    /// The size of a new presenter window on a screen with this visible size.
    public static func size(forVisibleScreen visible: CGSize) -> CGSize {
        CGSize(width: (visible.width * screenFraction).rounded(),
               height: (visible.height * screenFraction).rounded())
    }
}
