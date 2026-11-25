import SwiftUI

/// The presenter's toolbar items in one place, so their order and groups are fixed
/// (product-owner decision 2026-11-25, #189). From leading to trailing:
///
/// - Navigation: the system's sidebar button and Go Back.
/// - View: the Layout menu (arrangement, slot contents, notes mode), hidden in draw mode
///   (DRAW-05).
/// - Time: start or stop with a click, more in its menu.
/// - Live tools: Pointer, Curtain and Draw, with the drawing tools in draw mode.
/// - Output: the external display status (iPhone, iPad); the Mac's Start Presentation comes
///   from `presenterWindow(for:)`.
/// - Overflow: Import and Export and, from `settingsSheet()`, Settings (iPhone, iPad).
///
/// Fixed spacers separate the groups (the system draws the glass capsules). In compact sizes
/// the less important items (Go Back, Layout, Pointer, the external display status) go to the
/// overflow menu first, so Time, Curtain and Draw stay in the bar (`PresenterToolbarFocus`).
struct PresenterToolbar: ToolbarContent {
    let session: PresentationSession
    let focus: PresenterToolbarFocus
    @Binding var isSettingTimer: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: focus.placement(Self.goBackPlacement, isLessImportant: true)) {
            GoBackButton(session: session)
        }

        if session.curtain.isShown {
            ToolbarItem(placement: HiddenScreenWarning.placement) {
                HiddenScreenWarning()
            }
            // A status, not a button: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
        }

        // Layout changes are locked in draw mode (DRAW-05).
        if !session.drawing.isActive {
            ToolbarItem(placement: focus.placement(isLessImportant: true)) {
                PresenterLayoutMenu(session: session)
            }
            if focus.isInBar(isLessImportant: true) {
                ToolbarSpacer(.fixed)
            }
        }

        ToolbarItem(placement: focus.placement()) {
            TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, isInOverflow: !focus.isInBar())
        }
        if focus.isInBar() {
            ToolbarSpacer(.fixed)
        }

        ToolbarItem(placement: focus.placement(isLessImportant: true)) {
            PointerToolbarMenu(pointer: session.pointer)
        }
        ToolbarItem(placement: focus.placement()) {
            CurtainToolbarMenu(session: session)
        }
        // The drawing tools are the focused task's own items while drawing; while the notes
        // are edited in a compact bar, Draw makes room for Done (#152).
        DrawingToolbar(session: session, placement: focus == .notes ? focus.placement() : .automatic)

        #if os(iOS)
        if focus.isInBar(isLessImportant: true) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(placement: focus.placement(isLessImportant: true)) {
            // How to present on a second screen (#82); the Mac needs no hint.
            ExternalDisplayStatusButton()
        }
        // Notes, drawings and .slidepilot import and export (NOTES-06, DRAW-10, NOTES-11).
        ToolbarItem(placement: .secondaryAction) {
            FileTransferMenu()
        }
        #endif
    }

    #if os(macOS)
    private static let goBackPlacement = ToolbarItemPlacement.navigation
    #else
    // `.navigation` puts it at the trailing end of the iPad's document bar, next to the
    // display status; leading keeps it with the sidebar button and the title.
    private static let goBackPlacement = ToolbarItemPlacement.topBarLeading
    #endif
}
