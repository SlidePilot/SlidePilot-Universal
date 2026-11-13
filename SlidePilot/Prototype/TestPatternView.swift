import SwiftUI

// PROTOTYPE (issue #7).

/// Shows whether the presentation surface uses the display's native pixels:
/// stripes of exactly one device pixel look like an even grey only when the
/// image is not scaled. Also prints the size the view sees.
struct TestPatternView: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let pixel = 1 / displayScale
                // Border: one device pixel inside every edge.
                context.stroke(
                    Path(CGRect(origin: .zero, size: size).insetBy(dx: pixel / 2, dy: pixel / 2)),
                    with: .color(.white),
                    lineWidth: pixel
                )
                // Vertical one-pixel stripes in the left third, horizontal in the right third.
                let block = CGRect(x: size.width / 8, y: size.height / 4, width: size.width / 4, height: size.height / 2)
                var x = block.minX
                while x < block.maxX {
                    context.fill(Path(CGRect(x: x, y: block.minY, width: pixel, height: block.height)), with: .color(.white))
                    x += 2 * pixel
                }
                let block2 = CGRect(x: size.width * 5 / 8, y: size.height / 4, width: size.width / 4, height: size.height / 2)
                var y = block2.minY
                while y < block2.maxY {
                    context.fill(Path(CGRect(x: block2.minX, y: y, width: block2.width, height: pixel)), with: .color(.white))
                    y += 2 * pixel
                }
                // Centre cross.
                context.fill(Path(CGRect(x: size.width / 2 - pixel / 2, y: 0, width: pixel, height: size.height)), with: .color(.gray))
                context.fill(Path(CGRect(x: 0, y: size.height / 2 - pixel / 2, width: size.width, height: pixel)), with: .color(.gray))
            }
            .overlay(alignment: .top) {
                Text(verbatim: description(for: proxy.size))
                    .font(.title2.monospaced())
                    .foregroundStyle(.white)
                    .padding()
            }
        }
        .background(.black)
    }

    private func description(for size: CGSize) -> String {
        let width = Int((size.width * displayScale).rounded())
        let height = Int((size.height * displayScale).rounded())
        return "\(Int(size.width))×\(Int(size.height)) pt · @\(displayScale.formatted())x · \(width)×\(height) px"
    }
}
