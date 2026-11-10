import SlidePilotCore
import SlidePilotRemoteProtocol
import SlidePilotRendering
import SwiftUI

/// Placeholder shown until document handling exists (Phase 2).
struct ContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Presentation Open", systemImage: "rectangle.on.rectangle")
        } description: {
            Text("Open a PDF to start presenting.")
        } actions: {
            Text(verbatim: modulesSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Proves that all three packages are linked.
    private var modulesSummary: String {
        [SlidePilotCoreModule.name, SlidePilotRenderingModule.name, SlidePilotRemoteProtocolModule.name]
            .joined(separator: " · ")
    }
}

#Preview {
    ContentView()
}
