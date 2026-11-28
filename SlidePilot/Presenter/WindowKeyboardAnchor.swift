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
/// only sees presses while the window is the first responder, or a view that has no use
/// for these keys (`PassesSlideKeysToWindow`).
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

    /// AppKit may release the view without moving it out of its window first.
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class AnchorView: NSView {
        var handle: ((WindowKey) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Safe: local monitors run on the main thread, before AppKit dispatches the
                // event, so the event never leaves it; assumeIsolated traps otherwise.
                nonisolated(unsafe) let mainEvent = event
                let used = MainActor.assumeIsolated { self?.handled(mainEvent) == true }
                return used ? nil : event
            }
        }

        // Only listens; clicks go to the slides.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handled(_ event: NSEvent) -> Bool {
            guard let window, event.window === window,
                  window.firstResponder === window || window.firstResponder is PassesSlideKeysToWindow,
                  // ⌘ and ⌃ combinations stay with the menus (e.g. ⌃⌘→).
                  event.modifierFlags.isDisjoint(with: [.command, .control]),
                  let key = Self.key(for: event) else { return false }
            return handle?(key) == true
        }

        /// Arrows with ⇧ or ⌥ count too, like the SwiftUI key handlers; "." only plain,
        /// like `blackCurtainKey(_:)`.
        private static func key(for event: NSEvent) -> WindowKey? {
            switch event.specialKey {
            case .leftArrow?, .upArrow?, .pageUp?: .previous
            case .rightArrow?, .downArrow?, .pageDown?: .next
            default:
                event.charactersIgnoringModifiers == "."
                    && event.modifierFlags.isDisjoint(with: [.shift, .option]) ? .period : nil
            }
        }
    }
}

/// An AppKit view that takes the keyboard but leaves the slide keys and "." to its
/// window, like the drawing canvas (#246).
protocol PassesSlideKeysToWindow: NSView {}
#endif
