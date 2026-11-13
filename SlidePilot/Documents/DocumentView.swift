import SwiftUI

/// Content of a document window until the presenter view exists (#13, #14).
/// Shows that the PDF was opened and how many slides it has.
struct DocumentView: View {
    let title: String
    let pageCount: Int

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "rectangle.on.rectangle")
        } description: {
            Text("\(pageCount) slides")
        }
    }
}

extension DocumentView {
    init(document: PDFFileDocument, fileURL: URL?) {
        let title = fileURL?.deletingPathExtension().lastPathComponent
            ?? String(localized: "Untitled PDF")
        self.init(title: title, pageCount: document.info.pageCount)
    }
}

#Preview {
    DocumentView(title: "plain-slides", pageCount: 6)
}
