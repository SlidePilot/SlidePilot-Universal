#if os(macOS)
import AppKit
import SlidePilotCore
import SwiftUI

/// The mouse pointer that stands for the pointer over the current slide and the
/// presentation (PTR-06): the system cursor for Cursor and Hand, else the drawn pointer.
enum PointerCursor {
    /// Rendered once per configuration; the cursor is asked for on every redraw.
    private static var images: [PointerConfiguration: NSImage] = [:]

    static func style(for configuration: PointerConfiguration) -> PointerStyle {
        switch configuration.shape {
        case .cursor: return .default
        case .hand: return .link
        default:
            guard let image = image(for: configuration) else { return .default }
            return .image(Image(nsImage: image), hotSpot: .center)
        }
    }

    private static func image(for configuration: PointerConfiguration) -> NSImage? {
        if let image = images[configuration] {
            return image
        }
        let renderer = ImageRenderer(content: PointerImage(configuration: configuration))
        // Sharp on Retina screens; AppKit picks the matching representation.
        renderer.scale = 2
        let image = renderer.nsImage
        images[configuration] = image
        return image
    }
}
#endif
