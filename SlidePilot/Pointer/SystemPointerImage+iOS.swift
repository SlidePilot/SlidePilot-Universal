#if os(iOS)
import SlidePilotCore
import SwiftUI

/// iPadOS has no cursor images to borrow, so Cursor and Hand are SF Symbols, black with a
/// white outline like the Mac cursors, so they show on dark and light slides (PTR-03).
struct SystemPointerImage: View {
    let shape: PointerShape

    /// The cursor's size on the external display; fixed like the old app's pointers, which
    /// do not follow Dynamic Type.
    private static let pointSize: CGFloat = 26
    private static let outline: CGFloat = 1.5

    var body: some View {
        let symbol = Image(systemName: shape == .hand ? "hand.point.up.left.fill" : "cursorarrow")
            .font(.system(size: Self.pointSize))
        ZStack {
            // The outline: the symbol in white, moved a little in eight directions.
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) * .pi / 4
                symbol
                    .foregroundStyle(.white)
                    .offset(x: cos(angle) * Self.outline, y: sin(angle) * Self.outline)
            }
            symbol.foregroundStyle(.black)
        }
        .padding(Self.outline)
        .fixedSize()
    }

    /// The tip of the arrow and of the index finger.
    static func hotSpot(of shape: PointerShape) -> UnitPoint {
        shape == .hand ? UnitPoint(x: 0.3, y: 0.05) : UnitPoint(x: 0.2, y: 0.08)
    }
}
#endif
