#if os(iOS)
import SlidePilotCore
import SwiftUI

/// Two columns with a draggable separator for iPad (LAY-03).
///
/// Custom UI (ADR 0010): iPadOS has no resizable split view for arbitrary content
/// (`NavigationSplitView` only offers fixed sidebar widths). The separator is a system
/// separator line with a grip like the system's drag handles; it works with touch, the
/// pointer and VoiceOver. In portrait windows and when the columns do not fit side by side,
/// they stack vertically; the stored separator position stays unchanged.
struct TouchSplitView<Leading: View, Trailing: View>: View {
    let fraction: Double
    let onDrag: (Double) -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    private let lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if !PresenterSplit.stacksVertically(width: width, height: proxy.size.height, separatorWidth: lineWidth) {
                HStack(spacing: 0) {
                    leading
                        .frame(width: PresenterSplit.leadingWidth(fraction: fraction, width: width, separatorWidth: lineWidth))
                    SplitHandle(lineWidth: lineWidth, fraction: fraction) { leadingWidth in
                        onDrag(PresenterSplit.fraction(leadingWidth: leadingWidth, width: width, separatorWidth: lineWidth))
                    } adjust: { step in
                        let current = PresenterSplit.leadingWidth(fraction: fraction, width: width, separatorWidth: lineWidth)
                        onDrag(PresenterSplit.fraction(leadingWidth: current + step * width, width: width, separatorWidth: lineWidth))
                    }
                    trailing
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    leading
                        .frame(maxHeight: .infinity)
                    Divider()
                    trailing
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .coordinateSpace(.named(SplitHandle.space))
    }
}

/// The separator line with a grip and a wider touch area.
private struct SplitHandle: View {
    static let space = "TouchSplitView"

    let lineWidth: CGFloat
    let fraction: Double
    /// Called with the new leading width while dragging.
    let drag: (Double) -> Void
    /// Called with ±0.05 (a share of the width) by VoiceOver.
    let adjust: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: lineWidth)
            .overlay {
                Capsule()
                    .fill(isDragging ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 6, height: 44)
            }
            // A comfortable touch target around the 1 pt line.
            .frame(maxHeight: .infinity)
            .contentShape(.interaction, Rectangle().inset(by: -12))
            .contentShape(.hoverEffect, Capsule().inset(by: -6))
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        isDragging = true
                        drag(value.location.x)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Separator"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            .accessibilityHint(Text("Swipe up or down to resize the slides"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(0.05)
                case .decrement: adjust(-0.05)
                @unknown default: break
                }
            }
    }
}
#endif
