#if os(macOS)
import AppKit
import SwiftUI

/// Calls `reclaim` whenever the window is key and nothing in it has the keyboard, so the
/// slide keys work without a click (NAV-01, #120).
///
/// SwiftUI's focus state only receives key presses while its own responder is AppKit's
/// first responder. When a window opens (also a restored or second one), SwiftUI leaves
/// the window itself as first responder right after the slides took the focus, so the
/// focus state says "focused" but no key arrives. Checked one turn after the window
/// becomes key; a focused text field or list keeps the keyboard.
struct WindowKeyboardAnchor: NSViewRepresentable {
    let reclaim: () -> Void

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.reclaim = reclaim
    }

    final class AnchorView: NSView {
        var reclaim: (() -> Void)?
        private var keyChanges: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            keyChanges?.cancel()
            keyChanges = nil
            guard let window else { return }
            let becameKey = NotificationCenter.default.notifications(named: NSWindow.didBecomeKeyNotification, object: window)
            let isKey = window.isKeyWindow
            // Ends when the view leaves the window (above) or is released.
            keyChanges = Task { [weak self] in
                if isKey {
                    await self?.reclaimIfUnclaimed()
                }
                for await _ in becameKey {
                    await self?.reclaimIfUnclaimed()
                }
            }
        }

        // Only listens; clicks go to the slides.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func reclaimIfUnclaimed() async {
            // SwiftUI and AppKit settle the first responder after the key change.
            await Task.yield()
            guard let window, window.isKeyWindow, window.firstResponder === window else { return }
            reclaim?()
        }

        deinit {
            keyChanges?.cancel()
        }
    }
}
#endif
