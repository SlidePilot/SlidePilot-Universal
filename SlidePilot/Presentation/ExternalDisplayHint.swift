#if os(iOS)
import SlidePilotCore
import SwiftUI
import TipKit

/// Tells first-time users how to present on a second screen (#82): apps cannot start
/// Screen Mirroring, users start it in Control Center. Invalidated when it is dismissed,
/// when the status button is tapped or once an external display connects.
struct ExternalDisplayTip: Tip {
    var title: Text { Text("Present on a second screen") }
    var message: Text? { Text("Connect a display, or start Screen Mirroring in Control Center.") }
    var image: Image? { Image(systemName: ExternalDisplayStatusButton.mirroringSymbol) }
}

extension View {
    /// Adds the external-display status button to the presenter's toolbar and the tips above
    /// the slides (this one, then the pointer gesture's, PTR-01). Inline, because a popover
    /// tip on a toolbar item of a document window is never shown (iPadOS 27 simulator) and a
    /// popover on the slide would swallow the first swipe; a tip takes no space once it is
    /// invalidated.
    func externalDisplayHint() -> some View {
        modifier(ExternalDisplayHintModifier())
    }
}

private struct ExternalDisplayHintModifier: ViewModifier {
    @Environment(\.presenterToolbarFocus) private var focus
    @Environment(\.presenterMakesRoomForDrawing) private var makesRoomForDrawing
    /// Whether the display tip is gone, so the pointer tip may show (one tip at a time).
    @State private var displayTipIsDone = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: focus.placement(.primaryAction)) {
                    ExternalDisplayStatusButton()
                }
            }
            .safeAreaInset(edge: .top) {
                // Drawing keeps the room for the slide (#152).
                if !makesRoomForDrawing {
                    Group {
                        if displayTipIsDone {
                            TipView(TouchPointerTip())
                        } else {
                            TipView(ExternalDisplayTip())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .task {
                for await status in ExternalDisplayTip().statusUpdates {
                    if case .invalidated = status { displayTipIsDone = true }
                }
            }
    }
}

/// Shows whether the presentation is on an external display; tapping it explains how to
/// connect one, so the hint can be found again after the tip is gone.
struct ExternalDisplayStatusButton: View {
    /// The symbol Control Center uses for Screen Mirroring, so users recognize it.
    /// Nonisolated, because the tip's requirements are.
    nonisolated static let mirroringSymbol = "rectangle.on.rectangle"

    @Environment(ExternalDisplayStatus.self) private var status
    @State private var showsExplanation = false
    private let tip = ExternalDisplayTip()

    var body: some View {
        Button {
            tip.invalidate(reason: .actionPerformed)
            showsExplanation = true
        } label: {
            Label("External Display", systemImage: status.isConnected ? "rectangle.fill.on.rectangle.fill" : Self.mirroringSymbol)
        }
        .accessibilityValue(status.isConnected
            ? Text("Connected", comment: "Accessibility value of the external display button")
            : Text("Not connected", comment: "Accessibility value of the external display button"))
        .popover(isPresented: $showsExplanation) {
            ExternalDisplayExplanation(isConnected: status.isConnected)
        }
    }
}

private struct ExternalDisplayExplanation: View {
    let isConnected: Bool
    @ScaledMetric(relativeTo: .body) private var idealWidth = 320

    var body: some View {
        Group {
            if isConnected {
                Label("The presentation is shown on the external display.", systemImage: "checkmark.circle")
            } else {
                // The same text as the tip.
                Label {
                    VStack(alignment: .leading) {
                        ExternalDisplayTip().title
                            .font(.headline)
                        ExternalDisplayTip().message
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: ExternalDisplayStatusButton.mirroringSymbol)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(idealWidth: idealWidth)
        .presentationCompactAdaptation(.popover)
    }
}
#endif
