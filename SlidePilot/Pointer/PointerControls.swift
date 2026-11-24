import SlidePilotCore
import SwiftUI

/// Show Pointer (**C**), Pointer Appearance (**⌘1…⌘7**) and Edit Pointer… (**⌃⌥C**) in the
/// Presentation menu (PTR-01, PTR-02, PTR-04).
struct PointerMenuItems: View {
    @FocusedValue(\.slideNavigation) private var session
    // `nil` while the Set Timer sheet is open, so typing C there does not toggle the
    // pointer (the same rule as the curtain's B and W).
    @FocusedValue(\.presenterTimer) private var timer

    var body: some View {
        let session = timer == nil ? nil : session
        ShowPointerToggle(pointer: session?.pointer)
            .plainKeyShortcut("c")
        PointerAppearancePicker(pointer: session?.pointer, hasShortcuts: true)
        EditPointerMenuItem()
    }
}

/// Opens the Pointer settings with the custom pointer's editor (PTR-04), with the old app's
/// shortcut ⌃⌥C.
private struct EditPointerMenuItem: View {
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general
    #else
    @FocusedValue(\.showSettings) private var showSettings
    #endif

    var body: some View {
        #if os(macOS)
        Button("Edit Pointer…") {
            settingsTab = .pointer
            openSettings()
        }
        .keyboardShortcut("c", modifiers: [.control, .option])
        #else
        Button("Edit Pointer…") {
            showSettings?(.pointer)
        }
        .keyboardShortcut("c", modifiers: [.control, .option])
        .disabled(showSettings == nil)
        #endif
    }
}

/// The pointer's toolbar menu in the presenter: the same two controls as the menu bar.
struct PointerToolbarMenu: View {
    let pointer: PointerState

    var body: some View {
        Menu {
            ShowPointerToggle(pointer: pointer)
            PointerAppearancePicker(pointer: pointer, hasShortcuts: false)
        } label: {
            Label("Pointer", systemImage: pointer.isShown ? "cursorarrow.rays" : "cursorarrow")
        }
        .help(Text("Show the pointer on the presentation and choose its appearance"))
        // The icon alone tells sighted users whether the pointer is shown.
        .accessibilityValue(pointer.isShown ? Text("On") : Text("Off"))
    }
}

private struct ShowPointerToggle: View {
    let pointer: PointerState?

    var body: some View {
        Toggle(isOn: Binding { pointer?.isShown ?? false } set: { pointer?.isShown = $0 }) {
            Label("Show Pointer", systemImage: "cursorarrow.rays")
        }
        .disabled(pointer == nil)
    }
}

private struct PointerAppearancePicker: View {
    let pointer: PointerState?
    /// Only the menu bar shows the ⌘ shortcuts; a second set in the toolbar would clash.
    let hasShortcuts: Bool

    var body: some View {
        Picker(selection: Binding { pointer?.appearance ?? .cursor } set: { pointer?.appearance = $0 }) {
            ForEach(PointerAppearance.allCases, id: \.self) { appearance in
                if appearance == .individual {
                    Divider()
                }
                Label(appearance.title, systemImage: appearance.systemImage)
                    .tag(appearance)
                    .modifier(DigitShortcut(digit: hasShortcuts ? appearance.shortcutDigit : nil))
            }
        } label: {
            Label("Pointer Appearance", systemImage: "paintbrush.pointed")
        }
        .pickerStyle(.menu)
        .disabled(pointer == nil)
    }
}

private struct DigitShortcut: ViewModifier {
    let digit: Int?

    func body(content: Content) -> some View {
        if let digit, let character = String(digit).first {
            content.keyboardShortcut(KeyEquivalent(character), modifiers: .command)
        } else {
            content
        }
    }
}

extension PointerAppearance {
    /// The old app's menu titles.
    var title: LocalizedStringKey {
        switch self {
        case .cursor: "Cursor"
        case .hand: "Hand"
        case .dot: "Dot"
        case .circle: "Circle"
        case .targetBlack: "Target Black"
        case .targetRed: "Target Red"
        case .individual: "Individual"
        }
    }

    var systemImage: String {
        switch self {
        case .cursor: "cursorarrow"
        case .hand: "hand.point.up.left"
        case .dot: "circle.fill"
        case .circle: "circle"
        case .targetBlack, .targetRed: "scope"
        case .individual: "slider.horizontal.3"
        }
    }
}

extension View {
    /// The pointer's toolbar menu in the presenter (PTR-01, PTR-02).
    func pointerControls(_ session: PresentationSession) -> some View {
        modifier(PointerControlsModifier(pointer: session.pointer))
    }
}

private struct PointerControlsModifier: ViewModifier {
    let pointer: PointerState
    @Environment(\.presenterToolbarFocus) private var focus

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: focus.placement()) {
                PointerToolbarMenu(pointer: pointer)
            }
        }
    }
}
