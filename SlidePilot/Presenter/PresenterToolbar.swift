import SlidePilotCore
import SwiftUI

/// The presenter's toolbar items in one place, so their order and groups are fixed
/// (product-owner decision 2026-11-25, #189). From leading to trailing:
///
/// - Navigation: the sidebar button and Go Back.
/// - Time: start or stop with a click, more in its menu (`TimeToolbarMenu`).
/// - Live tools: Pointer, Curtain and Draw, with the drawing tools in draw mode.
/// - Mac: the Layout menu (arrangement, slot contents, notes mode), then Start Presentation,
///   always last.
/// - iPhone, iPad: the external display hint (only while no display is connected), then Layout, Import and Export, and Settings
///   in one group at the trailing end or, in compact sizes, as the last section of the
///   overflow menu.
///
/// Layout is hidden in draw mode (DRAW-05).
///
/// Fixed spacers separate the groups (the system draws the glass capsules). In compact sizes
/// the less important items (Go Back, Layout, Pointer, the external display status) go to the
/// overflow menu first, and Time, Curtain and Draw stay in the bar, in one capsule at the
/// leading edge. On iPad in portrait only Go Back leaves the leading edge for the secondary
/// actions, so the title has room (`PresenterToolbarFocus`, #207).
struct PresenterToolbar: ToolbarContent {
    let session: PresentationSession
    let focus: PresenterToolbarFocus
    @Binding var isSettingTimer: Bool
    #if os(iOS)
    @Environment(ExternalDisplayStatus.self) private var externalDisplay
    #endif

    var body: some ToolbarContent {
        navigationItems

        if session.curtain.isShown {
            ToolbarItem(placement: HiddenScreenWarning.placement) {
                HiddenScreenWarning(session: session)
            }
            // A status first: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
        }

        timeItems
        // A compact bar keeps Time, Curtain and Draw in one capsule at the leading edge (#207).
        if !focus.isCompact {
            ToolbarSpacer(.fixed)
        }

        ToolbarItem(placement: focus.placement(priority: .low)) {
            PointerToolbarMenu(pointer: session.pointer)
        }
        ToolbarItem(placement: focus.placement(Self.compactLeading(focus))) {
            CurtainToolbarMenu(session: session)
        }
        // The drawing tools are the focused task's own items while drawing; while the notes
        // are edited in a compact bar, Draw makes room for Done (#152).
        DrawingToolbar(
            session: session,
            placement: focus == .notes ? focus.placement() : .automatic,
            togglePlacement: focus == .notes ? focus.placement() : Self.compactLeading(focus),
            isCompact: focus.isCompact
        )

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
        ToolbarItem(placement: focus.placement(Self.goBackPlacement, priority: .lowest)) {
            GoBackButton(session: session)
        }
    }

    @ToolbarContentBuilder private var timeItems: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: focus.placement()) {
            TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .split)
        }
        #else
        if !focus.isCompact {
            // Two items in one glass capsule, like the Mac's split button (#189).
            ToolbarItem {
                TimeStartStopButton(session: session)
            }
            ToolbarItem {
                TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .options)
            }
        } else {
            ToolbarItem(placement: focus.placement(Self.compactLeading(focus))) {
                TimeToolbarMenu(session: session, isSettingTimer: $isSettingTimer, style: .compact)
            }
        }
        #endif
    }

    @ToolbarContentBuilder private var outputItems: some ToolbarContent {
        #if os(macOS)
        // Layout next to Start Presentation, which stays last (product-owner decision
        // 2026-11-25, #189). Layout changes are locked in draw mode (DRAW-05).
        if !session.drawing.isActive {
            ToolbarSpacer(.fixed)
            ToolbarItem {
                PresenterLayoutMenu(session: session)
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            StartPresentationButton()
        }
        #else
        // How to present on a second screen (#82); the Mac needs no hint, and neither does a
        // device that already presents on one.
        if !externalDisplay.isConnected {
            if focus.isInBar(priority: .low) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(placement: focus.placement(priority: .low)) {
                ExternalDisplayStatusButton()
            }
        }
        documentItems
        #endif
    }

    #if os(iOS)
    /// Layout, Import and Export, then Settings (product-owner decision 2026-11-25, #189): one
    /// group at the trailing edge, or the last section of the overflow menu. `.secondaryAction`
    /// would put them in the middle of the iPad's bar.
    @ToolbarContentBuilder private var documentItems: some ToolbarContent {
        if focus.isInBar(priority: .low) {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup {
                documentControls
            }
        } else {
            ToolbarItemGroup(placement: .secondaryAction) {
                // A section draws a separator above these items in the overflow menu.
                Section {
                    documentControls
                }
            }
        }
    }

    @ViewBuilder private var documentControls: some View {
        // Layout changes are locked in draw mode (DRAW-05).
        if !session.drawing.isActive {
            PresenterLayoutMenu(session: session)
        }
        // Notes, drawings and .slidepilot import and export (NOTES-06, DRAW-10, NOTES-11).
        FileTransferMenu()
        // The Mac has the Settings window instead (SET-01).
        SettingsToolbarButton()
    }
    #endif

    #if os(macOS)
    private static let goBackPlacement = ToolbarItemPlacement.navigation

    private static func compactLeading(_ focus: PresenterToolbarFocus) -> ToolbarItemPlacement {
        .automatic
    }
    #else
    /// iOS keeps the document title at its full width and moves trailing items into the
    /// overflow menu instead, so a phone in portrait kept Time and Curtain but not Draw. In a
    /// compact bar Time, Curtain and Draw go to the leading edge, where the title makes room
    /// (#207). Draw stays there in draw mode, so the toggle does not jump.
    private static func compactLeading(_ focus: PresenterToolbarFocus) -> ToolbarItemPlacement {
        focus.isCompact ? .topBarLeading : .automatic
    }

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
