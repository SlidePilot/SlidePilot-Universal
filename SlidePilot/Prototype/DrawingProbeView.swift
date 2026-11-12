import SlidePilotCore
import SwiftUI

/// Prototype UI for issue #11. English only, not localized, not for main.
struct DrawingProbeView: View {
    @State private var state = DrawingProbeState()

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    caption("Presenter (editable)")
                    SlideSurface(state: state, editable: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 8) {
                    caption("Presentation (read-only mirror)")
                    SlideSurface(state: state, editable: false)
                    caption("Thumbnail")
                    SlideSurface(state: state, editable: false)
                        .frame(width: 120)
                    caption("Log")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(state.log.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: line).font(.caption.monospaced())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 320)
            }
            .padding()
            .navigationTitle(Text(verbatim: "Drawing prototype"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker(selection: $state.fixture) {
                ForEach(DrawingProbeState.fixtures, id: \.self) { Text(verbatim: $0).tag($0) }
            } label: { Text(verbatim: "Fixture") }
            Stepper(value: $state.pageIndex, in: 0...max(state.pageCount - 1, 0)) {
                Text(verbatim: "Page \(state.pageIndex + 1)/\(state.pageCount)")
            }
            Picker(selection: $state.section) {
                ForEach(PageSection.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
            } label: { Text(verbatim: "Section") }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            Picker(selection: $state.engine) {
                ForEach(DrawingEngine.allCases) { Text(verbatim: $0.rawValue).tag($0) }
            } label: { Text(verbatim: "Engine") }
            .pickerStyle(.segmented)
            Toggle(isOn: $state.showsToolPicker) { Text(verbatim: "Tool picker") }
            Toggle(isOn: $state.pencilOnly) { Text(verbatim: "Pencil only") }
            Menu {
                Toggle(isOn: $state.interpolatedSampling) { Text(verbatim: "Sample rendered curve (2 pt)") }
                Toggle(isOn: $state.adaptsInkToDarkMode) { Text(verbatim: "Adapt ink to dark mode") }
            } label: { Label { Text(verbatim: "Options") } icon: { Image(systemName: "gearshape") } }
            #endif
            Picker(selection: $state.color) {
                ForEach(StrokeColor.presets, id: \.self) { color in
                    Text(verbatim: name(of: color)).tag(color)
                }
            } label: { Text(verbatim: "Color") }
            Button { state.undo() } label: { Label { Text(verbatim: "Undo") } icon: { Image(systemName: "arrow.uturn.backward") } }
                .disabled(!state.canUndo)
            Button { state.redo() } label: { Label { Text(verbatim: "Redo") } icon: { Image(systemName: "arrow.uturn.forward") } }
                .disabled(!state.canRedo)
            Button { state.clear() } label: { Label { Text(verbatim: "Clear") } icon: { Image(systemName: "trash") } }
            Button {
                state.setBackground(state.currentDrawing.background == .white ? .transparent : .white)
            } label: { Label { Text(verbatim: "White canvas") } icon: { Image(systemName: "rectangle.fill") } }
            Button { state.export() } label: { Label { Text(verbatim: "Export") } icon: { Image(systemName: "square.and.arrow.up") } }
        }
    }

    private func name(of color: StrokeColor) -> String {
        ["Black", "White", "Blue", "Green", "Magenta", "Orange"][StrokeColor.presets.firstIndex(of: color) ?? 0]
    }
}
