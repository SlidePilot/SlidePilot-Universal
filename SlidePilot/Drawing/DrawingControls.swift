import SlidePilotCore
import SlidePilotRendering
import SwiftUI

extension PresentationSession {
    /// Turns draw mode on (DRAW-01). The notes editor finishes and the navigator closes:
    /// layout changes are locked and slides cannot change while drawing (DRAW-05, NAV-04).
    func startDrawing() {
        guard !drawing.isActive else { return }
        notes.finishEditing()
        isNavigatorDisplayed = false
        drawing.start(onPage: currentPage)
    }

    /// Leaves draw mode (DRAW-01): Esc, Done or **D**.
    func stopDrawing() {
        drawing.stop(onPage: currentPage)
    }

    func toggleDrawing() {
        if drawing.isActive {
            stopDrawing()
        } else {
            startDrawing()
        }
    }
}

/// Draw, Clear Drawings, Clear Canvas and White Canvas in the Moderator menu, with the old
/// app's shortcuts (DRAW-01, DRAW-04).
struct DrawingMenuItems: View {
    @FocusedValue(\.slideNavigation) private var session

    var body: some View {
        Toggle("Draw", isOn: isDrawing)
            .plainKeyShortcut("d")
            .disabled(session == nil)
        Button("Clear Drawings") {
            guard let session else { return }
            session.drawing.clear(page: session.currentPage)
        }
        .keyboardShortcut("c", modifiers: .control)
        .disabled(!isActive)
        // The old app's names: Clear Canvas sets the transparent background and, like
        // every background change, removes the strokes (DRAW-04).
        Button("Clear Canvas") {
            setBackground(.transparent)
        }
        .keyboardShortcut("k", modifiers: .control)
        .disabled(!isActive)
        Button("White Canvas") {
            setBackground(.white)
        }
        .keyboardShortcut("k", modifiers: [.control, .shift])
        .disabled(!isActive)
    }

    private var isActive: Bool { session?.drawing.isActive == true }

    private var isDrawing: Binding<Bool> {
        Binding {
            isActive
        } set: { isOn in
            guard let session, isOn != session.drawing.isActive else { return }
            session.toggleDrawing()
        }
    }

    private func setBackground(_ background: CanvasBackground) {
        guard let session else { return }
        session.drawing.setBackground(background, onPage: session.currentPage)
    }
}

extension View {
    /// The Draw button, and in draw mode the drawing tools in the window's toolbar (DRAW-03).
    func drawingControls(_ session: PresentationSession) -> some View {
        modifier(DrawingControlsModifier(session: session))
    }

    /// Esc leaves draw mode (DRAW-01). Apply it outside the view that takes the keyboard.
    func drawingEscapeKey(_ session: PresentationSession) -> some View {
        onKeyPress(.escape) {
            guard session.drawing.isActive else { return .ignored }
            session.stopDrawing()
            return .handled
        }
    }
}

private struct DrawingControlsModifier: ViewModifier {
    let session: PresentationSession
    @Environment(\.presenterToolbarFocus) private var focus

    func body(content: Content) -> some View {
        content
            .toolbar {
                // The drawing tools are the focused task's own items while drawing; while
                // the notes are edited in a compact bar, Draw makes room for Done (#152).
                DrawingToolbar(session: session, placement: focus == .notes ? focus.placement() : .automatic)
            }
    }
}

/// Draw, and in draw mode color, Clear and the white canvas (DRAW-03, DRAW-04). Draw is a
/// toggle that stays in place and ends draw mode too, so the tools need no Done button,
/// which the full iPad toolbar would push into its overflow menu.
private struct DrawingToolbar: ToolbarContent {
    let session: PresentationSession
    let placement: ToolbarItemPlacement

    private var model: DrawingModel { session.drawing }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            Toggle("Draw", systemImage: "pencil.tip.crop.circle", isOn: isDrawing)
                .help(model.isActive ? Text("Stop drawing") : Text("Draw on the current slide"))
            if model.isActive {
                ColorButton(model: model)
                Button("Clear Drawings", systemImage: "eraser") {
                    model.clear(page: session.currentPage)
                }
                .help(Text("Remove all strokes from the slide"))
                // One toggle instead of a segmented picker: on iPad a segmented control
                // looks like a second toolbar inside the toolbar.
                Toggle("White Canvas", systemImage: "square.dashed", isOn: isWhiteCanvas)
                    .help(Text("White Canvas"))
            }
        }
    }

    private var isDrawing: Binding<Bool> {
        Binding {
            model.isActive
        } set: { isOn in
            guard isOn != model.isActive else { return }
            session.toggleDrawing()
        }
    }

    private var isWhiteCanvas: Binding<Bool> {
        Binding {
            model.drawings.drawing(onPage: session.currentPage).background == .white
        } set: {
            model.setBackground($0 ? .white : .transparent, onPage: session.currentPage)
        }
    }
}

/// Shows the current color; a click opens the six preset colors (DRAW-03). The Apple Pencil
/// opens the same popover (DRAW-11).
private struct ColorButton: View {
    @Bindable var model: DrawingModel
    /// About the size of a toolbar symbol, growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var swatchSize = 20.0

    var body: some View {
        Button {
            model.isColorPaletteShown.toggle()
        } label: {
            // A shape, not a symbol: toolbars tint symbol images, which would hide the
            // color, and show the title of a label whose icon is not a symbol.
            ColorSwatch(color: model.drawings.color)
                .frame(width: swatchSize, height: swatchSize)
        }
        .help(Text("Color"))
        .accessibilityLabel(Text("Color"))
        .accessibilityValue(model.drawings.color.name)
        .popover(isPresented: $model.isColorPaletteShown) {
            ColorPalette(model: model)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The current color: a dot inside a ring of the same color. The hairline keeps white
/// visible on a light bar and black on a dark one.
private struct ColorSwatch: View {
    let color: StrokeColor

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.swatch, lineWidth: 2)
            Circle()
                .fill(color.swatch)
                .scaleEffect(0.6)
        }
        .overlay {
            Circle().strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

/// The preset colors as a list; the current color has the list's selection. Choosing one
/// closes the popover.
private struct ColorPalette: View {
    let model: DrawingModel
    /// A list in a popover has no size of its own: the height of one row, growing with
    /// Dynamic Type, times the six presets.
    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var rowHeight = 32.0
    #else
    @ScaledMetric(relativeTo: .body) private var rowHeight = 50.0
    #endif
    @ScaledMetric(relativeTo: .body) private var width = 200.0
    @ScaledMetric(relativeTo: .body) private var swatchSize = 18.0

    var body: some View {
        List(selection: selection) {
            ForEach(StrokeColor.presets, id: \.self) { color in
                Label {
                    color.name
                } icon: {
                    // The same ring swatch as the toolbar's color button.
                    ColorSwatch(color: color)
                        .frame(width: swatchSize, height: swatchSize)
                }
                .tag(color)
                #if os(iOS)
                // Rows on the popover's own background, not a list inside the popover; the
                // current color in a bubble, like the selection of a Mac list.
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color == model.drawings.color ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear))
                        .padding(.horizontal, 8)
                )
                .listRowSeparator(.hidden)
                .accessibilityAddTraits(color == model.drawings.color ? .isSelected : [])
                #endif
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
        // Scrolls only when the largest text sizes need more than the estimated height.
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: width, minHeight: rowHeight * 3, idealHeight: rowHeight * Double(StrokeColor.presets.count) + 24)
    }

    private var selection: Binding<StrokeColor?> {
        Binding {
            model.drawings.color
        } set: {
            guard let color = $0 else { return }
            model.drawings.selectColor(color)
            model.isColorPaletteShown = false
        }
    }
}

extension StrokeColor {
    /// The stroke color as a SwiftUI color, for the color swatches.
    var swatch: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The old toolbar's color names.
    var name: Text {
        switch self {
        case .black: Text("Black")
        case .white: Text("White")
        case .blue: Text("Blue")
        case .green: Text("Green")
        case .magenta: Text("Magenta")
        case .orange: Text("Orange")
        default: Text("Custom Color")
        }
    }
}
