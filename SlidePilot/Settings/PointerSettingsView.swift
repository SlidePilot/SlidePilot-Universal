import CoreGraphics
import SlidePilotCore
import SwiftUI

/// The Pointer pane (PTR-04): edits the custom pointer of the Individual appearance, which
/// is global (PTR-05). Replaces the old preference pane with standard form controls
/// (ADR 0010); only the live preview is drawn, by the pointer overlay's own `PointerImage`.
///
/// The pane only provides form sections; `SettingsView` puts it into a form on each platform.
struct PointerSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let pointer = settings.individualPointer
        // Every stored pointer has an editor shape (`clampedForEditor`).
        let limits = pointer.shape.editorLimits ?? PointerShape.target.editorLimits!

        Section {
            PointerPreview(configuration: pointer)
            Picker("Shape", selection: shape) {
                ForEach(PointerShape.editorShapes, id: \.self) { shape in
                    Text(shape.editorTitle).tag(shape)
                }
            }
        } footer: {
            Text("Shown when the pointer appearance is Individual.")
        }

        Section {
            PointerSlider("Size", value: value(\.size), in: limits.size)
            // Dot and square have no thickness; the old app disabled the slider too.
            PointerSlider("Thickness", value: value(\.thickness), in: limits.thickness ?? 2...50)
                .disabled(limits.thickness == nil)
            ColorPicker("Color", selection: color(\.color), supportsOpacity: true)
        }

        Section {
            PointerSlider("Border width", value: value(\.borderWidth), in: limits.borderWidth)
            ColorPicker("Border color", selection: color(\.borderColor), supportsOpacity: true)
        }

        Section {
            PointerSlider("Shadow", value: value(\.shadowWidth), in: limits.shadowWidth)
        }
    }

    /// A new shape keeps the other values (DEF-14).
    private var shape: Binding<PointerShape> {
        Binding {
            settings.individualPointer.shape
        } set: {
            settings.individualPointer = settings.individualPointer.withShape($0)
        }
    }

    /// Whole points. Rounded here instead of a slider step, which would draw a tick per
    /// point on iPad.
    private func value(_ keyPath: WritableKeyPath<PointerConfiguration, Double>) -> Binding<Double> {
        Binding {
            settings.individualPointer[keyPath: keyPath]
        } set: {
            settings.individualPointer[keyPath: keyPath] = $0.rounded()
        }
    }

    /// Colors are stored as sRGB with alpha (PTR-05).
    private func color(_ keyPath: WritableKeyPath<PointerConfiguration, PointerColor>) -> Binding<CGColor> {
        Binding {
            settings.individualPointer[keyPath: keyPath].cgColor
        } set: { newValue in
            if let color = PointerColor(newValue) {
                settings.individualPointer[keyPath: keyPath] = color
            }
        }
    }
}

/// A labeled slider: the label in front of it on the Mac, above it on iPad, where a slider
/// alone shows no label.
private struct PointerSlider: View {
    let title: LocalizedStringKey
    let value: Binding<Double>
    let range: ClosedRange<Double>
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>) {
        self.title = title
        self.value = value
        self.range = range
    }

    var body: some View {
        #if os(macOS)
        // The Mac form lines labels up in a column of their own.
        slider
        #else
        // Above the slider, so all sliders are equally wide and long titles fit with
        // large Dynamic Type sizes.
        VStack(alignment: .leading) {
            Text(title)
                // A text does not dim by itself when disabled.
                .foregroundStyle(isEnabled ? .primary : .secondary)
                // The slider reads its own label.
                .accessibilityHidden(true)
            slider
                .labelsHidden()
        }
        #endif
    }

    private var slider: some View {
        Slider(value: value, in: range) {
            Text(title)
        }
        .accessibilityValue(Text("\(Int(value.wrappedValue)) points"))
    }
}

/// The pointer as the audience sees it, on the system's fill as backdrop (it follows light
/// and dark mode, so a black pointer is harder to see in dark mode). Large pointers are cut
/// off at the edges.
private struct PointerPreview: View {
    let configuration: PointerConfiguration

    var body: some View {
        PointerImage(configuration: configuration)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(.fill.secondary)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            // The shape picker below already reads the shape.
            .accessibilityLabel(Text("Pointer preview"))
    }
}

extension PointerShape {
    /// The old editor's shape names.
    var editorTitle: LocalizedStringKey {
        switch self {
        case .target: "Target"
        case .dot: "Dot"
        case .circle: "Circle"
        case .plus: "Plus"
        case .cross: "Cross"
        case .square: "Square"
        case .cursor: "Cursor"
        case .hand: "Hand"
        }
    }
}
