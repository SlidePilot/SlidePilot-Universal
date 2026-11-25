import SwiftUI

/// The presenter's toolbar items in one place, so their order and groups are fixed
/// (product-owner decision 2026-11-25, #189). From leading to trailing:
///
/// - Navigation: the sidebar button and Go Back.
/// - View: the Layout menu (arrangement, slot contents, notes mode), hidden in draw mode
///   (DRAW-05).
/// - Time: start or stop with a click, more in its menu (`TimeToolbarMenu`).
/// - Live tools: Pointer, Curtain and Draw, with the drawing tools in draw mode.
/// - Output: Start Presentation (Mac, always last) or the external display status (iPhone,
///   iPad).
/// - Files and settings (iPhone, iPad): Import and Export, then Settings, at the trailing end
///   or, in compact sizes, as the last items of the overflow menu.
///
/// Fixed spacers separate the groups (the system draws the glass capsules). In compact sizes
/// the less important items (Go Back, Layout, Pointer, the external display status) go to the
/// overflow menu first, so Time, Curtain and Draw stay in the bar (`PresenterToolbarFocus`).
struct PresenterToolbar: ToolbarContent {
    let session: PresentationSession
    let focus: PresenterToolbarFocus
    @Binding var isSettingTimer: Bool

    var body: some ToolbarContent {
        navigationItems

        if session.curtain.isShown {
            ToolbarItem(placement: HiddenScreenWarning.placement) {
                HiddenScreenWarning(session: session)
            }
            // A status first: no glass capsule around it.
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

        timeItems
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

        outputItems
    }

    // The groups below have their own builders: a ToolbarContentBuilder takes at most ten
    // items.

    @ToolbarContentBuilder private var navigationItems: some ToolbarContent {
        #if os(macOS)
        // The system's sidebar button ends up in the overflow menu while the sidebar is
        // closed, so the Mac gets its own at the leading end, like the iPad's.
        // Layout changes are locked in draw mode (DRAW-05).
        if !session.drawing.isActive {
            ToolbarItem(placement: .navigation) {
                SidebarButton(session: session)
            }
        }
        #endif
        ToolbarItem(placement: focus.placement(Self.goBackPlacement, isLessImportant: true)) {
            GoBackButton(session: session)
        }
    }

    @ToolbarContentBuilder private var timeItems: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: focus.placement()) {
            TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .split)
        }
        #else
        if focus == .none {
            // Two items in one glass capsule, like the Mac's split button (#189).
            ToolbarItem {
                TimeStartStopButton(session: session)
            }
            ToolbarItem {
                TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .options)
            }
        } else {
            ToolbarItem(placement: focus.placement()) {
                TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .compact)
            }
        }
        #endif
    }

    @ToolbarContentBuilder private var outputItems: some ToolbarContent {
        #if os(macOS)
        ToolbarSpacer(.fixed)
        ToolbarItem {
            StartPresentationButton()
        }
        #else
        if focus.isInBar(isLessImportant: true) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(placement: focus.placement(isLessImportant: true)) {
            // How to present on a second screen (#82); the Mac needs no hint.
            ExternalDisplayStatusButton()
        }
        // At the trailing edge, and the last two items of the overflow menu (product-owner
        // decision 2026-11-25, #189). `.secondaryAction` would put them in the middle of
        // the iPad's bar.
        if focus.isInBar(isLessImportant: true) {
            ToolbarSpacer(.fixed)
        }
        // Notes, drawings and .slidepilot import and export (NOTES-06, DRAW-10, NOTES-11).
        ToolbarItem(placement: focus.placement(isLessImportant: true)) {
            FileTransferMenu()
        }
        // The Mac has the Settings window instead (SET-01).
        ToolbarItem(placement: focus.placement(isLessImportant: true)) {
            SettingsToolbarButton()
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

#if os(macOS)
/// Shows or hides the slide navigator (LAY-06), like the system's sidebar button.
private struct SidebarButton: View {
    let session: PresentationSession

    var body: some View {
        Button(
            session.isNavigatorDisplayed ? "Hide Navigator" : "Show Navigator",
            systemImage: "sidebar.left"
        ) {
            session.isNavigatorDisplayed.toggle()
        }
        .help(Text(session.isNavigatorDisplayed ? "Hide the slide navigator" : "Show the slide navigator"))
    }
}

/// Starts the presentation in full screen (DOC-05).
private struct StartPresentationButton: View {
    @Environment(\.startPresentation) private var startPresentation

    var body: some View {
        Button("Start Presentation", systemImage: "play.rectangle") {
            startPresentation?()
        }
        .help(Text("Show the presentation in full screen"))
        .disabled(startPresentation == nil)
    }
}
#endif
