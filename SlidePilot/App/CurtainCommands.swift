import SlidePilotCore
import SwiftUI

/// Black Screen (B) and White Screen (W) in the Presentation menu (CUR-01). The old app's
/// hidden "." alternate for the black screen is a key press of the presenter and the
/// presentation, see `presenterCurtain(_:)`.
struct CurtainMenuItems: View {
    @FocusedValue(\.slideNavigation) private var session
    // `nil` while the Set Timer sheet is open, so typing B or W there does not toggle the
    // curtain (the same rule as the timer's plain-letter shortcuts).
    @FocusedValue(\.presenterTimer) private var timer

    var body: some View {
        let session = timer == nil ? nil : session
        CurtainToggle(curtain: .black, session: session)
            .keyboardShortcut("b", modifiers: [])
        CurtainToggle(curtain: .white, session: session)
            .keyboardShortcut("w", modifiers: [])
    }
}

/// A checkable menu item or toolbar button that shows or hides one curtain color.
struct CurtainToggle: View {
    let curtain: Curtain
    let session: PresentationSession?

    var body: some View {
        // Read here, not only in the binding, so the view observes the curtain.
        let isShown = session?.curtain == curtain
        Toggle(isOn: Binding { isShown } set: { session?.curtain.set(curtain, shown: $0) }) {
            switch curtain {
            case .white:
                Label("White Screen", systemImage: "rectangle")
            default:
                Label("Black Screen", systemImage: "rectangle.fill")
            }
        }
        .disabled(session == nil)
    }
}
