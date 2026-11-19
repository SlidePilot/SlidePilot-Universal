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

    func body(content: Content) -> some View {
        content
            .toolbar {
                if session.drawing.isActive {
                    DrawingToolbar(session: session)
                } else {
                    ToolbarItem {
                        Button("Draw", systemImage: "pencil.tip.crop.circle") {
                            session.startDrawing()
                        }
                        .help(Text("Draw on the current slide"))
                    }
                }
            }
    }
}

/// Color, Clear, canvas background and Done (DRAW-03, DRAW-04). Standard toolbar items:
/// the current color is visible and the presets are one click away (ADR 0016).
private struct DrawingToolbar: ToolbarContent {
    let session: PresentationSession

    private var model: DrawingModel { session.drawing }

    var body: some ToolbarContent {
        ToolbarItem {
            ColorButton(model: model)
        }
        ToolbarItem {
            Button("Clear Drawings", systemImage: "eraser") {
                model.clear(page: session.currentPage)
            }
            .help(Text("Remove all strokes from the slide"))
        }
        ToolbarItem {
            Picker("Canvas Background", selection: background) {
                Label("Transparent Canvas", systemImage: "square.dashed")
                    .tag(CanvasBackground.transparent)
                Label("White Canvas", systemImage: "square.fill")
                    .tag(CanvasBackground.white)
            }
            .pickerStyle(.segmented)
            .help(Text("Canvas Background"))
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                session.stopDrawing()
            }
            .help(Text("Stop drawing"))
        }
    }

    private var background: Binding<CanvasBackground> {
        Binding {
            model.drawings.drawing(onPage: session.currentPage).background
        } set: {
            model.setBackground($0, onPage: session.currentPage)
        }
    }
}

/// Shows the current color; a click opens the six preset colors (DRAW-03). The Apple Pencil
/// opens the same popover (DRAW-11).
private struct ColorButton: View {
    @Bindable var model: DrawingModel

    var body: some View {
        Button {
            model.isColorPaletteShown.toggle()
        } label: {
            Label {
                Text("Color")
            } icon: {
                Image(systemName: "circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(model.drawings.color.swatch)
            }
        }
        .help(Text("Color"))
        .accessibilityValue(model.drawings.color.name)
        .popover(isPresented: $model.isColorPaletteShown) {
            ColorPalette(model: model)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The preset colors as a standard picker; choosing one closes the popover.
private struct ColorPalette: View {
    let model: DrawingModel

    var body: some View {
        Form {
            Picker("Color", selection: selection) {
                ForEach(StrokeColor.presets, id: \.self) { color in
                    Label {
                        color.name
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(color.swatch)
                            // White and black stay visible on any popover background.
                            .overlay {
                                Image(systemName: "circle")
                                    .foregroundStyle(.separator)
                            }
                    }
                    .tag(color)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        #if os(macOS)
        .padding()
        #else
        .frame(idealWidth: 240, idealHeight: 340)
        #endif
    }

    private var selection: Binding<StrokeColor> {
        Binding {
            model.drawings.color
        } set: {
            model.drawings.selectColor($0)
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
