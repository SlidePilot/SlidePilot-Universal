import SwiftUI

// PROTOTYPE (issue #11): drawing probe. Never merged into main.
// main opens PDFs with DocumentGroup; this branch shows the probe instead.

@main
struct SlidePilotApp: App {
    var body: some Scene {
        WindowGroup {
            DrawingProbeView()
        }
    }
}
