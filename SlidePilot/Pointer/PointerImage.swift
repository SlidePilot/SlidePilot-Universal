import SlidePilotCore
import SwiftUI

/// One pointer as the audience sees it (PTR-03). Part of the pointer overlay, one of the
/// places where ADR 0010 allows custom drawing: the shapes are the old app's, drawn from
/// `PointerDrawing`; cursor and hand are system pointer images (`SystemPointerImage`).
struct PointerImage: View {
    let configuration: PointerConfiguration

    var body: some View {
        if let drawing = PointerDrawing(configuration) {
            Canvas { context, _ in
                Self.draw(drawing, in: &context)
            }
            .frame(width: drawing.side, height: drawing.side)
        } else {
            SystemPointerImage(shape: configuration.shape)
        }
    }

    /// The point of the image that marks the pointed-at spot: the center of drawn shapes,
    /// the tip of the system images.
    static func hotSpot(of configuration: PointerConfiguration) -> UnitPoint {
        configuration.shape.isSystemImage ? SystemPointerImage.hotSpot(of: configuration.shape) : .center
    }

    private static func draw(_ drawing: PointerDrawing, in context: inout GraphicsContext) {
        if drawing.shadowRadius > 0 {
            context.addFilter(.shadow(color: .black, radius: drawing.shadowRadius))
        }
        // One layer, so the shadow falls around the whole pointer like the old app's.
        context.drawLayer { layer in
            let center = drawing.side / 2
            layer.translateBy(x: center, y: center)
            layer.rotate(by: .degrees(drawing.rotation))
            layer.translateBy(x: -center, y: -center)
            for part in drawing.parts {
                switch part {
                case .fillEllipse(let rect, let color):
                    layer.fill(Path(ellipseIn: rect), with: .color(Color(color)))
                case .strokeEllipse(let rect, let lineWidth, let color):
                    layer.stroke(Path(ellipseIn: rect), with: .color(Color(color)), lineWidth: lineWidth)
                case .fillRect(let rect, let color):
                    layer.fill(Path(rect), with: .color(Color(color)))
                }
            }
        }
    }
}

extension Color {
    /// A pointer color; stored as sRGB (PTR-05).
    init(_ color: PointerColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
