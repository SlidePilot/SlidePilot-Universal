import QuickLook
import SlidePilotCore
import SwiftUI

extension View {
    /// Videos and `run:` links of the document (NAV-06, NAV-07): asks once for access to the
    /// PDF's folder when the PDF refers to files there, opens `run:` targets and reports
    /// problems with them.
    func linkedFiles(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(LinkedFilesModifier(session: session, linkedFiles: session.linkedFiles, fileURL: fileURL))
    }
}

private struct LinkedFilesModifier: ViewModifier {
    let session: PresentationSession
    @Bindable var linkedFiles: LinkedFiles
    let fileURL: URL?

    private struct Prepare: Equatable {
        let fileURL: URL?
        let cache: ObjectIdentifier
    }

    func body(content: Content) -> some View {
        content
            .environment(linkedFiles)
            // Again after a recompile: the new PDF may refer to other files (DOC-08).
            .task(id: Prepare(fileURL: fileURL, cache: ObjectIdentifier(session.cache))) {
                // First: `reloaded` resolves the videos against the document URL set here.
                await linkedFiles.prepare(documentURL: fileURL, cache: session.cache)
                guard !Task.isCancelled else { return }
                await linkedFiles.reloaded(page: session.currentPage, cache: session.cache)
            }
            .onChange(of: session.currentPage, initial: true) { _, page in
                linkedFiles.showPage(page)
            }
            .alert(Text("Allow Access to the Folder?"), isPresented: $linkedFiles.isAskingForFolderAccess) {
                Button("Allow Access…") { linkedFiles.requestFolderAccess() }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("This PDF contains videos or links to files next to it. To play and open them, choose the folder that contains the PDF. SlidePilot remembers it for all PDFs in that folder.")
            }
            // On a view of its own: the dialog texts are environment values and would
            // otherwise reach every open and save panel of the window.
            .background {
                Color.clear
                    .fileImporter(isPresented: $linkedFiles.isPickingFolder, allowedContentTypes: [.folder]) { result in
                        if case .success(let folder) = result {
                            linkedFiles.grantAccess(to: folder)
                        }
                    }
                    .fileDialogDefaultDirectory(linkedFiles.documentFolder)
                    .fileDialogMessage(Text("Choose the folder that contains the PDF and its videos."))
                    .fileDialogConfirmationLabel(Text("Allow Access"))
            }
            .alert(
                problemTitle,
                isPresented: Binding(get: { linkedFiles.problem != nil }, set: { if !$0 { linkedFiles.problem = nil } }),
                presenting: linkedFiles.problem
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { problem in
                switch problem {
                case .notFound: Text("Check that the file is in the place the PDF expects, relative to the PDF.")
                case .refused: Text("Links in a PDF can open documents and videos, but not programs or scripts.")
                }
            }
            .quickLookPreview($linkedFiles.previewURL)
    }

    private var problemTitle: Text {
        switch linkedFiles.problem {
        case .notFound(let name): Text("The file “\(name)” could not be found.")
        case .refused(let name): Text("SlidePilot does not open “\(name)”.")
        case nil: Text(verbatim: "")
        }
    }
}
