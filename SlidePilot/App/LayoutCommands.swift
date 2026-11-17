import SlidePilotCore
import SwiftUI

extension FocusedValues {
    /// The presenter layout of the focused document window (LAY-01, LAY-02).
    @Entry var presenterLayout: PresenterLayoutModel?
}

/// Arrangement and slot toggles in the View menu (LAY-01, LAY-02). The old app had them in
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
        ArrangementPicker(layout: layout)
            .pickerStyle(.menu)
        SlotToggle(layout: layout, slot: .current)
            .keyboardShortcut("a", modifiers: [])
        SlotToggle(layout: layout, slot: .next)
            .keyboardShortcut("p", modifiers: [])
        SlotToggle(layout: layout, slot: .notes)
            .keyboardShortcut("n", modifiers: [])
    }
}

/// The layout controls in the presenter's toolbar (LAY-01, LAY-02).
struct PresenterLayoutToolbar: ToolbarContent {
    let layout: PresenterLayoutModel

    var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                ArrangementPicker(layout: layout)
                    .pickerStyle(.inline)
            } label: {
                Label("Arrangement", systemImage: layout.arrangement.systemImage)
            }
            .help(Text("Arrangement"))
        }
        ToolbarItem {
            ControlGroup {
                ForEach(PresenterSlot.allCases, id: \.self) { slot in
                    SlotToggle(layout: layout, slot: slot)
                        .help(slot.title)
                }
            } label: {
                Label("Slides", systemImage: "rectangle.on.rectangle")
            }
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

    var systemImage: String {
        switch self {
        case .current: "rectangle.inset.filled"
        case .next: "rectangle.righthalf.inset.filled.arrow.right"
        case .notes: "note.text"
        }
    }
}

extension UserDefaultsPresenterLayoutStore {
    /// The app's last-used layout (LAY-05). Tests inject their own store.
    static let app = UserDefaultsPresenterLayoutStore(defaults: .standard)
}

extension View {
    /// Adds the layout controls to the toolbar and the menu commands of this window.
    func presenterLayoutControls(_ layout: PresenterLayoutModel) -> some View {
        toolbar { PresenterLayoutToolbar(layout: layout) }
            .focusedSceneValue(\.presenterLayout, layout)
    }
}
