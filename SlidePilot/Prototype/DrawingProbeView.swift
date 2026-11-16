import SlidePilotCore
import SwiftUI

/// Prototype UI for issue #11. English only, not localized, not for main.
///
/// The toolbar keeps every control labelled and readable down to an iPad mini
/// in portrait: settings live in labelled menus, page navigation sits below
/// the slide, and portrait orientation stacks the mirror below the presenter.
struct DrawingProbeView: View {
    @State private var state = DrawingProbeState()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    HStack(alignment: .top, spacing: 16) {
                        presenter
                        sidePanel
                            .frame(width: min(320, geometry.size.width * 0.3))
                    }
                    .padding()
                } else {
                    // Portrait: the log sits next to the mirror, so PencilKit's
                    // floating tool picker at the bottom does not cover it.
                    VStack(alignment: .leading, spacing: 16) {
                        presenter
                        HStack(alignment: .top, spacing: 16) {
                            mirrorPanel
                            logPanel
                        }
                    }
                    .padding()
                }
            }
            #if os(macOS)
            .navigationTitle(Text(verbatim: "Drawing prototype"))
            #else
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
    }

    // MARK: Content

    private var presenter: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Presenter (editable) – \(state.engine.rawValue)")
            ProbeSlideSurface(state: state, editable: true)
            pageNavigation
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var pageNavigation: some View {
        HStack {
            Button { state.pageIndex -= 1 } label: {
                Label { Text(verbatim: "Previous page") } icon: { Image(systemName: "chevron.left") }
            }
            .disabled(state.pageIndex == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])
            Text(verbatim: "Page \(state.pageIndex + 1) of \(state.pageCount)")
                .monospacedDigit()
            Button { state.pageIndex += 1 } label: {
                Label { Text(verbatim: "Next page") } icon: { Image(systemName: "chevron.right") }
            }
            .disabled(state.pageIndex >= state.pageCount - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            mirrorPanel
            logPanel
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var mirrorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Presentation (read-only mirror)")
            ProbeSlideSurface(state: state, editable: false)
            caption("Thumbnail")
            ProbeSlideSurface(state: state, editable: false)
                .frame(width: 120)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                caption("Log")
                Spacer()
                Button { copyLog() } label: {
                    Label { Text(verbatim: "Copy Log") } icon: { Image(systemName: "doc.on.doc") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.log.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.log.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.caption.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Puts the whole log on the clipboard so testers can paste it into a report.
    private func copyLog() {
        let text = state.log.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        state.record("Copied \(state.log.count) log lines")
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            documentMenu
        }
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            engineMenu
            optionsMenu
            #endif
            colorMenu
            Button { state.undo() } label: { Label { Text(verbatim: "Undo") } icon: { Image(systemName: "arrow.uturn.backward") } }
                .disabled(!state.canUndo)
            Button { state.redo() } label: { Label { Text(verbatim: "Redo") } icon: { Image(systemName: "arrow.uturn.forward") } }
                .disabled(!state.canRedo)
            Button { state.clear() } label: { Label { Text(verbatim: "Clear page") } icon: { Image(systemName: "trash") } }
            Button {
                state.setBackground(state.currentDrawing.background == .white ? .transparent : .white)
            } label: {
                Label { Text(verbatim: "White canvas") } icon: {
                    Image(systemName: state.currentDrawing.background == .white ? "rectangle.fill" : "rectangle")
                }
            }
            Button { state.export() } label: { Label { Text(verbatim: "Export to PDF") } icon: { Image(systemName: "square.and.arrow.up") } }
        }
    }

    /// Fixture and page section; the label shows both current values.
    private var documentMenu: some View {
        Menu {
            Picker(selection: $state.fixture) {
                ForEach(DrawingProbeState.fixtures, id: \.self) { Text(verbatim: $0).tag($0) }
            } label: { Text(verbatim: "Fixture") }
            Picker(selection: $state.section) {
                ForEach([PageSection.full, .left], id: \.self) { section in
                    Text(verbatim: section == .full ? "Full page" : "Left half (slide only)").tag(section)
                }
            } label: { Text(verbatim: "Section") }
        } label: {
            Text(verbatim: "\(state.fixture) · \(state.section == .full ? "full" : state.section.rawValue)")
        }
    }

    #if os(iOS)
    private var engineMenu: some View {
        Picker(selection: $state.engine) {
            ForEach(DrawingEngine.allCases) { Text(verbatim: $0.rawValue).tag($0) }
        } label: { Text(verbatim: "Engine") }
        .pickerStyle(.menu)
    }

    private var optionsMenu: some View {
        Menu {
            Section {
                Toggle(isOn: $state.showsToolPicker) { Text(verbatim: "Show tool picker") }
                Toggle(isOn: $state.pencilOnly) { Text(verbatim: "Pencil only (finger does not draw)") }
                Toggle(isOn: $state.liveMirrorsPencilKit) { Text(verbatim: "Mirror strokes live") }
            } header: { Text(verbatim: "PencilKit") }
            Section {
                Toggle(isOn: $state.interpolatedSampling) { Text(verbatim: "Sample rendered curve (2 pt)") }
                Toggle(isOn: $state.adaptsInkToDarkMode) { Text(verbatim: "Adapt ink to dark mode") }
            } header: { Text(verbatim: "Advanced") }
        } label: { Label { Text(verbatim: "Options") } icon: { Image(systemName: "gearshape") } }
    }
    #endif

    private var colorMenu: some View {
        Menu {
            Picker(selection: $state.color) {
                ForEach(StrokeColor.presets, id: \.self) { color in
                    Text(verbatim: name(of: color)).tag(color)
                }
            } label: { Text(verbatim: "Color") }
            .pickerStyle(.inline)
        } label: {
            Label { Text(verbatim: "Color: \(name(of: state.color))") } icon: { Image(systemName: "paintpalette") }
        }
    }

    private func name(of color: StrokeColor) -> String {
        ["Black", "White", "Blue", "Green", "Magenta", "Orange"][StrokeColor.presets.firstIndex(of: color) ?? 0]
    }
}
