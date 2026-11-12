import SwiftUI

// PROTOTYPE (issue #10): open a PDF through DocumentGroup and watch it for changes. Never merged into main.

@main
struct SlidePilotApp: App {
    var body: some Scene {
        DocumentGroup(viewing: ReloadProbeDocument.self) { file in
            if let url = file.fileURL {
                ReloadProbeView(url: url, document: file.document)
            } else {
                ContentUnavailableView {
                    Label { Text(verbatim: "No File URL") } icon: { Image(systemName: "questionmark.folder") }
                } description: {
                    Text(verbatim: "The document system did not provide a file URL.")
                }
            }
        }
    }
}
