#if os(macOS)
import AppKit
import SlidePilotCore
import SwiftUI

/// The Cursor and Hand pointers are the system's arrow and pointing-hand cursors, like in
/// the old app (PTR-03).
struct SystemPointerImage: View {
    let shape: PointerShape

    var body: some View {
        let cursor = Self.cursor(for: shape)
        Image(nsImage: cursor.image)
            .frame(width: cursor.image.size.width, height: cursor.image.size.height)
    }

    /// The cursor's hot spot; AppKit measures it from the image's top left corner.
    static func hotSpot(of shape: PointerShape) -> UnitPoint {
        let cursor = cursor(for: shape)
        let size = cursor.image.size
        guard size.width > 0, size.height > 0 else { return .topLeading }
        return UnitPoint(x: cursor.hotSpot.x / size.width, y: cursor.hotSpot.y / size.height)
    }

    private static func cursor(for shape: PointerShape) -> NSCursor {
        shape == .hand ? .pointingHand : .arrow
    }
}
#endif
