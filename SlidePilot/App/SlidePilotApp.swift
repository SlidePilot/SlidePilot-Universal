import SwiftUI

// PROTOTYPE (issue #9): open PDFs through DocumentGroup and probe file access. Never merged into main.

@main
struct SlidePilotApp: App {
    var body: some Scene {
        DocumentGroup(viewing: ProbeDocument.self) { file in
            if let url = file.fileURL {
                ProbeView(pdfURL: url, deliveredByteCount: file.document.deliveredByteCount)
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
