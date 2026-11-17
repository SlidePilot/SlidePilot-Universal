#if os(macOS)
import AppKit
import SlidePilotCore
import SwiftUI

/// Two columns with a draggable separator, backed by `NSSplitView` (LAY-03).
///
/// SwiftUI's `HSplitView` looks the same but cannot set or report the separator position,
/// which the layout stores (LAY-05). This wrapper keeps the system separator and only adds
/// that: the stored fraction is applied on changes and window resizing, and the user's drags
/// are reported back. Both columns are at least `PresenterSplit.minimumColumnWidth` wide.
struct MacSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    /// The leading column's share of the width.
    let fraction: Double
    let onDrag: (Double) -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    func makeNSView(context: Context) -> FractionSplitView {
        let splitView = FractionSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        // Frame-based like the old app: with arranged subviews, Auto Layout would move the
        // separator by holding priority and undo the stored position.
        splitView.addSubview(column(leading))
        splitView.addSubview(column(trailing))
        return splitView
    }

    func updateNSView(_ splitView: FractionSplitView, context: Context) {
        context.coordinator.onDrag = onDrag
        (splitView.subviews[0] as? NSHostingView<Leading>)?.rootView = leading
        (splitView.subviews[1] as? NSHostingView<Trailing>)?.rootView = trailing
        splitView.fraction = fraction
    }

    /// The split view sizes the columns; their content does not push back.
    private func column<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = []
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrag: onDrag)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var onDrag: (Double) -> Void

        init(onDrag: @escaping (Double) -> Void) {
            self.onDrag = onDrag
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            max(proposedMinimumPosition, PresenterSplit.minimumColumnWidth)
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            min(proposedMaximumPosition, splitView.bounds.width - splitView.dividerThickness - PresenterSplit.minimumColumnWidth)
        }

        /// Window resizing keeps the separator at the stored share of the width.
        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            (splitView as? FractionSplitView)?.applyFraction()
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // AppKit names the divider only when the user drags it, not on window resizing
            // or `setPosition`.
            guard notification.userInfo?["NSSplitViewDividerIndex"] != nil,
                  let splitView = notification.object as? FractionSplitView,
                  let leading = splitView.subviews.first
            else { return }
            let fraction = PresenterSplit.fraction(
                leadingWidth: leading.frame.width,
                width: splitView.bounds.width,
                separatorWidth: splitView.dividerThickness
            )
            splitView.fraction = fraction
            onDrag(fraction)
        }
    }
}

/// An `NSSplitView` that keeps its separator at `fraction` of the width.
final class FractionSplitView: NSSplitView {
    var fraction: Double = 0.5 {
        didSet {
            if fraction != oldValue { applyFraction() }
        }
    }

    /// Lays out both columns for `fraction`, keeping each at least the minimum width.
    func applyFraction() {
        guard subviews.count == 2 else { return }
        let width = bounds.width
        let leading = PresenterSplit.leadingWidth(fraction: fraction, width: width, separatorWidth: dividerThickness).rounded()
        let trailingX = leading + dividerThickness
        subviews[0].frame = CGRect(x: 0, y: 0, width: leading, height: bounds.height)
        subviews[1].frame = CGRect(x: trailingX, y: 0, width: max(width - trailingX, 0), height: bounds.height)
        needsDisplay = true
    }
}
#endif
