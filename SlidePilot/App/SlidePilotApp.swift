import SwiftUI

@main
struct SlidePilotApp: App {
    var body: some Scene {
        // One window per PDF (DOC-01/02). The system provides the open panel at launch,
        // File ▸ Open, Open Recent and Close on the Mac and the document browser on iPad.
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            DocumentView(document: file.document)
        }
    }
}
