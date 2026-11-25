import SlidePilotCore
import SwiftUI

extension FocusedValues {
    /// The presenter layout of the focused document window (LAY-01, LAY-02).
    @Entry var presenterLayout: PresenterLayoutModel?
}

/// Arrangement, slot contents and slot toggles in the View menu (LAY-01, LAY-02, LAY-04). The old app had them in
/// the Moderator and Notes menus; the plain-key shortcuts A, P and N are the same.
struct LayoutCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .toolbar) {
            LayoutMenuItems()
            Divider()
        }
    }
}

private struct LayoutMenuItems: View {
    @FocusedValue(\.presenterLayout) private var layout

    var body: some View {
        Menu {
            ArrangementMenuContent(layout: layout)
        } label: {
            Label("Arrangement", systemImage: (layout?.arrangement ?? .double).systemImage)
        }
        .disabled(layout == nil)
        SlotToggle(layout: layout, slot: .current)
            .plainKeyShortcut("a")
        SlotToggle(layout: layout, slot: .next)
            .plainKeyShortcut("p")
        SlotToggle(layout: layout, slot: .notes)
            .plainKeyShortcut("n")
        NotesModeMenuItems()
    }
}

/// The Layout menu in the presenter's toolbar: arrangement, slot contents and notes mode in
/// one menu (LAY-01, LAY-04, NOTES-01; product-owner decision 2026-11-25, #189). The slot
/// toggles stay in the View menu only, since next to this menu they made the toolbar
/// confusing (product-owner decision 2026-11-19); the menu still reaches every layout.
struct PresenterLayoutMenu: View {
    let session: PresentationSession

    var body: some View {
        Menu {
            ArrangementMenuContent(layout: session.layout)
            Divider()
            NotesModeMenus(session: session)
        } label: {
            // The remote's Layout button uses the same symbol (REM-07).
            Label("Layout", systemImage: "rectangle.3.group")
        }
        .help(Text("Layout"))
    }
}

/// The arrangement and, for each visible slot, which slide it shows (LAY-01, LAY-04): in
/// View ▸ Arrangement and in the toolbar's Layout menu. The slot pickers replace the
/// old layout editor's drag and drop (product-owner decision 2026-11-18).
private struct ArrangementMenuContent: View {
    let layout: PresenterLayoutModel?

    var body: some View {
        ArrangementPicker(layout: layout)
            .pickerStyle(.inline)
        if let layout {
            Divider()
            ForEach(layout.arrangement.slotIndicesInVisualOrder, id: \.self) { index in
                SlotContentPicker(layout: layout, index: index)
                    .pickerStyle(.menu)
            }
        }
    }
}

/// Chooses the slide shown in one slot. Choosing a slide shown elsewhere swaps the two;
/// choosing a hidden one hides the slide that was there, like dropping a slide symbol on a
/// slot in the old layout editor (LAY-04).
private struct SlotContentPicker: View {
    let layout: PresenterLayoutModel
    let index: Int

    var body: some View {
        if let place = layout.arrangement.place(ofSlotAt: index, stacked: layout.isStacked) {
            Picker(selection: selection) {
                ForEach(PresenterSlot.allCases, id: \.self) { slot in
                    Label(slot.contentTitle, systemImage: slot.systemImage)
                        .tag(slot)
                }
            } label: {
                // The subtitle shows the slot's slide without opening the submenu.
                Text(place.title)
                Text(layout.layout.slots[index].contentTitle)
            }
        }
    }

    private var selection: Binding<PresenterSlot> {
        Binding {
            layout.layout.slots[index]
        } set: {
            layout.setSlot($0, at: index)
        }
    }
}

/// Chooses single, double, triple left or triple right (LAY-01).
private struct ArrangementPicker: View {
    let layout: PresenterLayoutModel?

    var body: some View {
        Picker(selection: selection) {
            ForEach(PresenterArrangement.allCases, id: \.self) { arrangement in
                Label(arrangement.title, systemImage: arrangement.systemImage)
                    .tag(arrangement)
            }
        } label: {
            Label("Arrangement", systemImage: (layout?.arrangement ?? .double).systemImage)
        }
        .disabled(layout == nil)
    }

    private var selection: Binding<PresenterArrangement> {
        Binding {
            layout?.arrangement ?? .double
        } set: {
            layout?.setArrangement($0)
        }
    }
}

/// Shows or hides one slot (LAY-02).
private struct SlotToggle: View {
    let layout: PresenterLayoutModel?
    let slot: PresenterSlot

    var body: some View {
        Toggle(isOn: isOn) {
            Label(slot.title, systemImage: slot.systemImage)
        }
        .disabled(layout == nil)
    }

    private var isOn: Binding<Bool> {
        Binding {
            layout?.isVisible(slot) ?? false
        } set: {
            layout?.setVisible(slot, $0)
        }
    }
}

extension PresenterArrangement {
    var title: LocalizedStringKey {
        switch self {
        case .single: "Single Slide"
        case .double: "Two Slides"
        case .tripleLeft: "Three Slides, Large Left"
        case .tripleRight: "Three Slides, Large Right"
        }
    }

    var systemImage: String {
        switch self {
        case .single: "rectangle"
        case .double: "rectangle.split.2x1"
        // The large slot is drawn on its side; slides do not mirror for right-to-left.
        case .tripleLeft: "sidebar.squares.right"
        case .tripleRight: "sidebar.squares.left"
        }
    }
}

extension PresenterSlot {
    /// The old app's menu titles.
    var title: LocalizedStringKey {
        switch self {
        case .current: "Show Current Slide"
        case .next: "Preview Next Slide"
        case .notes: "Show Notes"
        }
    }

    /// What the slot shows, for the slot pickers (LAY-04).
    var contentTitle: LocalizedStringKey {
        switch self {
        case .current: "Current Slide"
        case .next: "Next Slide"
        case .notes: "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .current: "rectangle.inset.filled"
        case .next: "rectangle.righthalf.inset.filled.arrow.right"
        case .notes: "note.text"
        }
    }
}

extension PresenterSlotPlace {
    /// The slot's place in the window, as the slot picker's title (LAY-04).
    var title: LocalizedStringKey {
        switch self {
        case .whole: "Slide"
        case .left: "Left"
        case .right: "Right"
        case .largeLeft: "Large Left"
        case .topRight: "Top Right"
        case .bottomRight: "Bottom Right"
        case .topLeft: "Top Left"
        case .bottomLeft: "Bottom Left"
        case .largeRight: "Large Right"
        case .top: "Top"
        case .middle: "Middle"
        case .bottom: "Bottom"
        }
    }
}

extension UserDefaultsPresenterLayoutStore {
    /// The app's last-used layout (LAY-05). Tests inject their own store.
    static let app = UserDefaultsPresenterLayoutStore(defaults: .standard)
}

extension View {
    /// The layout menu commands of this window, off while `isLocked` (draw mode, DRAW-05).
    /// The toolbar's Layout menu is hidden then too (`PresenterToolbar`).
    func presenterLayoutControls(_ layout: PresenterLayoutModel, isLocked: Bool = false) -> some View {
        focusedSceneValue(\.presenterLayout, isLocked ? nil : layout)
    }
}
