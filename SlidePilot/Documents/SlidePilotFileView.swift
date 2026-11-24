import SlidePilotCore
import SlidePilotRendering
import SwiftUI
import UniformTypeIdentifiers

/// A `.slidepilot` file opened on its own (double-click, AirDrop, Open With, File ▸ Open):
/// what it holds, and the PDF to import it into (NOTES-11).
///
/// An open PDF gets the file through its session; its window asks before replacing
/// anything. A PDF that is not open gets the data in its stored entry after a confirmation
/// here, and the Mac opens it.
struct SlidePilotFileView: View {
    let document: SlidePilotFileDocument
    let fileURL: URL?

    @Environment(SessionRegistry.self) private var registry
    /// Missing in previews; drawings then are not imported, as with the setting off.
    @Environment(AppSettings.self) private var settings: AppSettings?
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif
    @Environment(\.dismiss) private var dismiss

    /// The import into a PDF that is not open, waiting for the user's confirmation.
    private struct PendingImport: Identifiable {
        let id = UUID()
        let file: SlidePilotFile
        let pdf: URL
        let entry: CompanionEntry
        let check: SlidePilotFileImportCheck
    }

    /// The open document to import into.
    @State private var target: PresentationSession.ID?
    @State private var isChoosingPDF = false
    @State private var isImporting = false
    @State private var pendingImport: PendingImport?
    /// iPad: the PDF the data was stored for, until the user closed the message.
    @State private var importedPDFName: String?
    @State private var failureMessage: String?
    #if os(macOS)
    /// `dismiss` does not close a document window on the Mac.
    @State private var window = FileWindowReference()
    #endif

    private var fileName: String {
        fileURL?.lastPathComponent ?? SlidePilotFile.exportName(forPDFNamed: nil)
    }

    private var savesDrawings: Bool { settings?.savesDrawings ?? false }

    /// The open documents with a file, by file name.
    private var openDocuments: [PresentationSession] {
        registry.sessions.filter { $0.fileURL != nil }
            .sorted { pdfName(of: $0).localizedStandardCompare(pdfName(of: $1)) == .orderedAscending }
    }

    private func pdfName(of session: PresentationSession) -> String {
        session.fileURL?.lastPathComponent ?? session.title
    }

    var body: some View {
        Group {
            switch document.content {
            case .success(let file):
                form(file)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Can’t Import This File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(SlidePilotFileView.message(for: error, fileName: fileName))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 340, idealHeight: 400)
        .background(WindowBridge { [window] in window.window = $0 })
        #endif
        .alert(
            pendingImport?.check.replacesData == false
                ? Text("Import the SlidePilot File?")
                : Text("Replace the Data of “\(pendingImport?.entry.pdf.fileName ?? "")”?"),
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { pending in
            Button("Import", role: pending.check.replacesData ? .destructive : nil) {
                Task { await storeImport(pending) }
            }
            Button("Cancel", role: .cancel) { isImporting = false }
        } message: { pending in
            Text(pending.check.confirmationMessage ?? "")
        }
        .alert(
            Text("Data Imported"),
            isPresented: Binding(get: { importedPDFName != nil }, set: { if !$0 { importedPDFName = nil } }),
            presenting: importedPDFName
        ) { _ in
            Button("OK") { close() }
        } message: { pdfName in
            Text("Open “\(pdfName)” to present with the imported notes, drawings and settings.")
        }
        .alert(
            Text("The SlidePilot File Couldn’t Be Imported"),
            isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } }),
            presenting: failureMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func form(_ file: SlidePilotFile) -> some View {
        Form {
            Section {
                LabeledContent("PDF", value: file.pdfFileName)
                LabeledContent("Pages", value: file.pdfPageCount.formatted())
                LabeledContent("Contains") {
                    Text(file.kinds.isEmpty
                        ? String(localized: "No stored data")
                        : file.kinds.map { String(localized: $0.title) }.formatted(.list(type: .and)))
                }
                LabeledContent("Exported") {
                    Text(file.exportedAt, format: .dateTime.day().month().year().hour().minute())
                }
            } header: {
                Text(fileName)
            }
            Section {
                if openDocuments.isEmpty {
                    Text("No PDF is open. Choose the PDF to import the file into.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Open PDFs", selection: $target) {
                        ForEach(openDocuments) { session in
                            Text(pdfName(of: session)).tag(Optional(session.id))
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.radioGroup)
                    #else
                    .pickerStyle(.inline)
                    #endif
                }
                HStack {
                    Button("Choose PDF…") { isChoosingPDF = true }
                        .disabled(isImporting)
                    if isImporting {
                        // Reading a large PDF, or one still in iCloud, can take a moment.
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Import Into")
            } footer: {
                Text("The notes, drawings and settings in this file replace those of the PDF. SlidePilot asks before replacing stored data.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fileName)
        .toolbar {
            // Only for an open PDF; Choose PDF… imports on its own.
            if !openDocuments.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    importButton(file)
                }
            }
        }
        .fileImporter(isPresented: $isChoosingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(file, intoPDFAt: url) }
        }
        .fileDialogConfirmationLabel(Text("Choose"))
        .onChange(of: openDocuments.map(\.id), initial: true) { _, ids in
            if let target, !ids.contains(target) {
                self.target = nil
            }
            target = target ?? defaultTarget(for: file)
        }
    }

    private func importButton(_ file: SlidePilotFile) -> some View {
        Button("Import") {
            if let session = openDocuments.first(where: { $0.id == target }) {
                hand(file, to: session)
            }
        }
        .disabled(target == nil || isImporting)
        .keyboardShortcut(.defaultAction)
    }

    /// The open PDF with the file's PDF name, or the only open PDF.
    private func defaultTarget(for file: SlidePilotFile) -> PresentationSession.ID? {
        let documents = openDocuments
        return (documents.first { pdfName(of: $0) == file.pdfFileName } ?? (documents.count == 1 ? documents[0] : nil))?.id
    }

    /// Hands the file to an open document, whose window asks before importing. Closing this
    /// window brings that one forward.
    private func hand(_ file: SlidePilotFile, to session: PresentationSession) {
        session.slidePilotFileRequest = SlidePilotFileRequest(file: file, fileName: fileName)
        close()
    }

    /// Closes this file's window once the import is handed on.
    private func close() {
        #if os(macOS)
        window.window?.close()
        #else
        dismiss()
        #endif
    }

    /// Imports into a chosen PDF: through its window when it is open, into its stored entry
    /// otherwise.
    private func importFile(_ file: SlidePilotFile, intoPDFAt url: URL) async {
        isImporting = true
        // Stays on while the confirmation is up; `storeImport` ends it.
        var finished = true
        defer { if finished { isImporting = false } }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let store = CompanionStore.app else {
            failureMessage = String(localized: "SlidePilot can’t store data for PDFs on this device.")
            return
        }
        let pageCount: Int
        do {
            pageCount = try await Self.pageCount(ofPDFAt: url)
        } catch {
            failureMessage = String(localized: "“\(url.lastPathComponent)” couldn’t be opened as a PDF.")
            return
        }
        // Records an open of the PDF (SET-03) even if the import is cancelled: choosing the
        // PDF counts as using it, and the entry's match is refreshed for its next open.
        guard let opening = await store.open(pdfAt: url, pageCount: pageCount) else {
            failureMessage = String(localized: "SlidePilot can’t store data for “\(url.lastPathComponent)”.")
            return
        }
        // Open already, maybe under another URL form: its window imports, so its next save
        // does not write the old data back.
        if let session = registry.sessions.first(where: { $0.companion.entry?.id == opening.entry.id }) {
            hand(file, to: session)
            return
        }
        let check = SlidePilotFileImportCheck(
            file: file, fileName: fileName, pdfFileName: url.lastPathComponent, pageCount: pageCount,
            hasData: opening.entry.hasStoredData, savesDrawings: savesDrawings
        )
        let pending = PendingImport(file: file, pdf: url, entry: opening.entry, check: check)
        if check.confirmationMessage == nil {
            await storeImport(pending)
        } else {
            finished = false
            pendingImport = pending
        }
    }

    /// Stores the data for a PDF that is not open; the Mac then opens it.
    ///
    /// The PDF may have been opened while the confirmation was up: its window holds the old
    /// entry and would write it back over the import, so the file goes to that window
    /// instead. One that opens during the write gets it too.
    private func storeImport(_ pending: PendingImport) async {
        defer { isImporting = false }
        guard let store = CompanionStore.app else { return }
        if let session = openSession(for: pending) {
            hand(pending.file, to: session)
            return
        }
        guard let stored = await store.importFile(pending.file, into: pending.entry, includingDrawings: savesDrawings) else {
            failureMessage = String(localized: "SlidePilot can’t store data for “\(pending.pdf.lastPathComponent)”.")
            return
        }
        if let session = openSession(for: pending), session.companion.entry != stored {
            hand(pending.file, to: session)
            return
        }
        #if os(macOS)
        let isAccessing = pending.pdf.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { pending.pdf.stopAccessingSecurityScopedResource() }
        }
        do {
            try await openDocument(at: pending.pdf)
            close()
        } catch {
            importedPDFName = pending.entry.pdf.fileName
        }
        #else
        importedPDFName = pending.entry.pdf.fileName
        #endif
    }

    /// An open window of the pending import's PDF, also one whose data is still loading.
    private func openSession(for pending: PendingImport) -> PresentationSession? {
        let path = pending.pdf.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return registry.sessions.first { session in
            session.companion.entry?.id == pending.entry.id
                || session.fileURL?.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false) == path
        }
    }

    /// Reads the PDF off the main actor; coordinated, so a file in iCloud Drive is downloaded.
    /// The coordinated read blocks one thread of the pool until then, which is acceptable for
    /// a single import the user started.
    @concurrent
    private static func pageCount(ofPDFAt url: URL) async throws -> Int {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try PDFInspector.inspect(result.get()).pageCount
    }

    static func message(for error: SlidePilotFileFormat.DecodingError, fileName: String) -> String {
        switch error {
        case .unreadable:
            String(localized: "“\(fileName)” isn’t a SlidePilot file, or it is damaged.")
        case .newerVersion:
            String(localized: "“\(fileName)” was exported by a newer version of SlidePilot. Update SlidePilot to import it.")
        }
    }
}

#if os(macOS)
/// The window of an opened `.slidepilot` file. A reference, so storing it does not redraw.
private final class FileWindowReference {
    weak var window: NSWindow?
}
#endif
