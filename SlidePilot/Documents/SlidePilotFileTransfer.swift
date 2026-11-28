import SlidePilotCore
import SwiftUI
import UniformTypeIdentifiers

/// A `.slidepilot` file handed to an open document by the file's own window (NOTES-11).
struct SlidePilotFileRequest: Identifiable {
    let id = UUID()
    let file: SlidePilotFile
    /// The `.slidepilot` file's name, for messages.
    let fileName: String
}

/// What importing a `.slidepilot` file into a PDF would do (NOTES-11): it imports at once
/// when nothing is replaced, nothing differs and nothing is left out; otherwise the user
/// confirms after reading why.
struct SlidePilotFileImportCheck {
    let replacesData: Bool
    /// `nil` when the import needs no confirmation.
    let confirmationMessage: String?

    init(file: SlidePilotFile, fileName: String, pdfFileName: String?, pageCount: Int, hasData: Bool, savesDrawings: Bool) {
        let mismatch = file.mismatch(withPDFNamed: pdfFileName, pageCount: pageCount)
        let skipsDrawings = file.drawings != nil && !savesDrawings
        replacesData = hasData
        var paragraphs: [String] = []
        if hasData && savesDrawings {
            paragraphs.append(String(localized: "The notes and drawings of this PDF are replaced by those in “\(fileName)”, and its settings are applied. This can’t be undone."))
        } else if hasData {
            paragraphs.append(String(localized: "The notes of this PDF are replaced by those in “\(fileName)”, and its settings are applied. This can’t be undone."))
        }
        if mismatch.contains(.fileName) {
            paragraphs.append(String(localized: "The file was exported for “\(file.pdfFileName)”."))
        }
        if mismatch.contains(.pageCount) {
            paragraphs.append(String(localized: "The file was exported for a PDF with a different number of pages (\(file.pdfPageCount) instead of \(pageCount))."))
        }
        if skipsDrawings {
            paragraphs.append(String(localized: "The drawings in the file aren’t imported because Save drawings is off."))
        }
        confirmationMessage = paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n")
    }
}

/// Import and Export SlidePilot File… of the focused presenter window (NOTES-11).
struct FocusedSlidePilotFile {
    let importFile: () -> Void
    let exportFile: () -> Void
    /// The same export for the iPad share sheet.
    let shareItem: SlidePilotFileExport
}

extension FocusedValues {
    @Entry var slidePilotFile: FocusedSlidePilotFile?
}

extension EnvironmentValues {
    /// The same commands for the iPad toolbar menu, which focused values do not reach.
    @Entry var slidePilotFile: FocusedSlidePilotFile?
}

/// File ▸ Import SlidePilot File… and Export SlidePilot File…, after the notes and drawings
/// commands. No shortcuts: ⇧⌘O and ⇧⌘E are the notes', ⌥⌘E the drawings' (ADR 0019).
struct SlidePilotFileCommands: Commands {
    static let importSymbol = "arrow.down.doc"
    static let exportSymbol = "doc.badge.arrow.up"

    var body: some Commands {
        CommandGroup(after: .importExport) {
            SlidePilotFileMenuItems()
        }
    }
}

private struct SlidePilotFileMenuItems: View {
    @FocusedValue(\.slidePilotFile) private var slidePilotFile

    var body: some View {
        Divider()
        Button("Import SlidePilot File…") { slidePilotFile?.importFile() }
            .disabled(slidePilotFile == nil)
        Button("Export SlidePilot File…") { slidePilotFile?.exportFile() }
            .disabled(slidePilotFile == nil)
    }
}

extension View {
    /// Exports the document's notes, drawings and settings as a `.slidepilot` file and
    /// imports one (NOTES-11).
    func slidePilotFileTransfer(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(SlidePilotFileTransferModifier(session: session, fileURL: fileURL))
    }
}

private struct SlidePilotFileTransferModifier: ViewModifier {
    let session: PresentationSession
    let fileURL: URL?

    /// Missing in snapshots; drawings then are not imported, as with the setting off.
    @Environment(AppSettings.self) private var settings: AppSettings?

    /// A file waiting for the user to confirm the import.
    private struct PendingImport: Identifiable {
        let id = UUID()
        let file: SlidePilotFile
        let fileName: String
        let message: String
        let replacesData: Bool
    }

    private struct Failure {
        let title: LocalizedStringKey
        let message: String
    }

    /// Runs the request check again when a request arrives or the entry loads.
    private struct RequestTrigger: Hashable {
        let requestID: UUID?
        let entryID: UUID?
    }

    @State private var isImporting = false
    @State private var exportDocument: SlidePilotFileDocument?
    @State private var pendingImport: PendingImport?
    @State private var failure: Failure?

    private var companion: DocumentCompanion { session.companion }
    private var savesDrawings: Bool { settings?.savesDrawings ?? false }

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.slidePilotFile, slidePilotFileCommands)
            .environment(\.slidePilotFile, slidePilotFileCommands)
            .onChange(of: fileURL, initial: true) { _, fileURL in
                session.fileURL = fileURL
            }
            // On a view of its own: the notes' importer is on the content, and two importers
            // on the same view would not both work.
            .background {
                Color.clear
                    .fileImporter(isPresented: $isImporting, allowedContentTypes: UTType.slidePilotFileTypes) { result in
                        // A short task on the main actor; a result after the window closed is
                        // dropped because the entry is gone.
                        guard case .success(let url) = result else { return }
                        Task { await read(url) }
                    }
                    #if os(macOS)
                    .fileDialogMessage(Text("Choose a SlidePilot file to import into this PDF."))
                    #endif
                    .fileDialogConfirmationLabel(Text("Import"))
            }
            .fileExporter(
                isPresented: $exportDocument.isPresented,
                document: exportDocument,
                contentType: .slidePilotFile,
                defaultFilename: exportName
            ) { result in
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    failure = Failure(title: "The SlidePilot File Couldn’t Be Exported", message: error.localizedDescription)
                }
            }
            // A `.slidepilot` file opened on its own and applied to this PDF.
            .task(id: RequestTrigger(requestID: session.slidePilotFileRequest?.id, entryID: companion.entry?.id)) {
                guard companion.entry != nil, let request = session.slidePilotFileRequest else { return }
                session.slidePilotFileRequest = nil
                begin(request.file, named: request.fileName)
            }
            .alert(
                Text(pendingImport?.replacesData == true ? "Replace the Data of This PDF?" : "Import the SlidePilot File?"),
                isPresented: $pendingImport.isPresented,
                presenting: pendingImport
            ) { pending in
                Button("Import", role: pending.replacesData ? .destructive : nil) {
                    apply(pending.file)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(pending.message)
            }
            .alert(
                failure.map { Text($0.title) } ?? Text(verbatim: ""),
                isPresented: $failure.isPresented,
                presenting: failure
            ) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure.message)
            }
    }

    /// Off in draw mode (DRAW-05): an import would replace the drawing being edited.
    private var slidePilotFileCommands: FocusedSlidePilotFile? {
        companion.entry != nil && !session.drawing.isActive ? FocusedSlidePilotFile(
            importFile: { isImporting = true },
            exportFile: export,
            shareItem: shareItem
        ) : nil
    }

    // MARK: - Export

    private var exportName: String {
        SlidePilotFile.exportName(forPDFNamed: fileURL?.lastPathComponent)
    }

    private func export() {
        session.notes.finishEditing()
        guard let file = companion.exportFile() else { return }
        exportDocument = SlidePilotFileDocument(file: file)
    }

    private var shareItem: SlidePilotFileExport {
        SlidePilotFileExport(fileName: exportName) { [session] in
            await MainActor.run {
                session.notes.finishEditing()
                return session.companion.exportFile()
            }
        }
    }

    // MARK: - Import

    private func read(_ url: URL) async {
        let entryID = companion.entry?.id
        do {
            let file = try await Self.readFile(url)
            guard !Task.isCancelled, entryID != nil, companion.entry?.id == entryID else { return }
            begin(file, named: url.lastPathComponent)
        } catch let error as SlidePilotFileFormat.DecodingError {
            failure = Failure(title: "The SlidePilot File Couldn’t Be Imported", message: SlidePilotFileView.message(for: error, fileName: url.lastPathComponent))
        } catch {
            failure = Failure(title: "The SlidePilot File Couldn’t Be Imported", message: error.localizedDescription)
        }
    }

    /// Reads and decodes off the main actor; coordinated, so a file in iCloud Drive is
    /// downloaded first. That blocks one thread of the pool meanwhile, which is acceptable for
    /// a single import the user started.
    @concurrent
    private static func readFile(_ url: URL) async throws -> SlidePilotFile {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try SlidePilotFileFormat.decode(CoordinatedFileRead.data(at: url))
    }

    /// Imports at once when nothing would be replaced and nothing differs; asks otherwise.
    private func begin(_ file: SlidePilotFile, named fileName: String) {
        let check = SlidePilotFileImportCheck(
            file: file, fileName: fileName,
            pdfFileName: fileURL?.lastPathComponent, pageCount: session.cache.info.pageCount,
            hasData: companion.entry?.hasStoredData == true || !session.drawing.drawings.pages.isEmpty,
            savesDrawings: savesDrawings
        )
        if let message = check.confirmationMessage {
            pendingImport = PendingImport(file: file, fileName: fileName, message: message, replacesData: check.replacesData)
        } else {
            apply(file)
        }
    }

    private func apply(_ file: SlidePilotFile) {
        session.notes.finishEditing()
        let savesDrawings = savesDrawings
        guard let settings = companion.importFile(file, includingDrawings: savesDrawings) else { return }
        if savesDrawings {
            // Replaces the drawings on screen; their changes reach the companion again.
            session.drawing.deleteAll()
            session.drawing.drawings.loadStoredPages(file.drawings?.pages ?? [:])
        }
        session.applyStoredSettings(settings)
    }
}
