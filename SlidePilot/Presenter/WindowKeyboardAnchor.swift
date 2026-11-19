#if os(macOS)
import AppKit
import SwiftUI

/// The slide keys for a window in which nothing has the keyboard, like the old app's
/// window-level key handling (NAV-01, CUR-01, #120).
///
/// SwiftUI's key handlers only receive presses while a SwiftUI view is AppKit's first
/// responder. Right after a window opens (also a restored or second one), or once a
/// focused control goes away, the window itself is first responder and the keys would be
/// lost until a click. A focused text field, list or the notes keep their keys: this
/// only sees presses while the window is the first responder.
struct WindowKeyboardAnchor: NSViewRepresentable {
    /// Handles a press; returns `true` if it was used.
    let handle: (WindowKey) -> Bool

    enum WindowKey {
        case previous, next, period
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.handle = handle
    }

    final class AnchorView: NSView {
        var handle: ((WindowKey) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Safe: local monitors run on the main thread, before AppKit dispatches the
                // event, so the event never leaves the main thread.
                nonisolated(unsafe) let mainEvent = event
                let used = MainActor.assumeIsolated { self?.handled(mainEvent) == true }
                return used ? nil : event
            }
        }

        // Only listens; clicks go to the slides.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func handled(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, window.firstResponder === window,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  let key = Self.key(for: event) else { return false }
            return handle?(key) == true
        }

        private static func key(for event: NSEvent) -> WindowKey? {
            switch event.specialKey {
            case .leftArrow?, .upArrow?, .pageUp?: .previous
            case .rightArrow?, .downArrow?, .pageDown?: .next
            default: event.charactersIgnoringModifiers == "." && !event.modifierFlags.contains(.shift) ? .period : nil
            }
        }
    }
}
#endif
