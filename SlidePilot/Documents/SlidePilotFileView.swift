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
        #endif
        .alert(
            Text("Replace the Data of “\(pendingImport?.entry.pdf.fileName ?? "")”?"),
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { pending in
            Button("Import", role: pending.check.replacesData ? .destructive : nil) {
                Task { await storeImport(pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.check.confirmationMessage ?? "")
        }
        .alert(
            Text("Data Imported"),
            isPresented: Binding(get: { importedPDFName != nil }, set: { if !$0 { importedPDFName = nil } }),
            presenting: importedPDFName
        ) { _ in
            Button("OK") { dismiss() }
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
                Button("Choose PDF…") { isChoosingPDF = true }
                    .disabled(isImporting)
            } header: {
                Text("Import Into")
            } footer: {
                Text("The notes, drawings and settings in this file replace those of the PDF. SlidePilot asks before replacing stored data.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fileName)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    if let session = openDocuments.first(where: { $0.id == target }) {
                        Task { await hand(file, to: session) }
                    }
                }
                .disabled(target == nil || isImporting)
                .keyboardShortcut(.defaultAction)
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

    /// The open PDF with the file's PDF name, or the only open PDF.
    private func defaultTarget(for file: SlidePilotFile) -> PresentationSession.ID? {
        let documents = openDocuments
        return (documents.first { pdfName(of: $0) == file.pdfFileName } ?? (documents.count == 1 ? documents[0] : nil))?.id
    }

    /// Hands the file to an open document, whose window asks before importing, and brings
    /// that window forward on the Mac.
    private func hand(_ file: SlidePilotFile, to session: PresentationSession) async {
        session.slidePilotFileRequest = SlidePilotFileRequest(file: file, fileName: fileName)
        #if os(macOS)
        if let url = session.fileURL {
            _ = try? await openDocument(at: url)
        }
        #endif
        dismiss()
    }

    /// Imports into a chosen PDF: through its window when it is open, into its stored entry
    /// otherwise.
    private func importFile(_ file: SlidePilotFile, intoPDFAt url: URL) async {
        isImporting = true
        defer { isImporting = false }
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
        guard let opening = await store.open(pdfAt: url, pageCount: pageCount) else {
            failureMessage = String(localized: "SlidePilot can’t store data for “\(url.lastPathComponent)”.")
            return
        }
        // Open already, maybe under another URL form: its window imports, so its next save
        // does not write the old data back.
        if let session = registry.sessions.first(where: { $0.companion.entry?.id == opening.entry.id }) {
            await hand(file, to: session)
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
            pendingImport = pending
        }
    }

    /// Stores the data for a PDF that is not open; the Mac then opens it.
    private func storeImport(_ pending: PendingImport) async {
        guard let store = CompanionStore.app else { return }
        _ = await store.importFile(pending.file, into: pending.entry, includingDrawings: savesDrawings)
        #if os(macOS)
        do {
            try await openDocument(at: pending.pdf)
            dismiss()
        } catch {
            importedPDFName = pending.entry.pdf.fileName
        }
        #else
        importedPDFName = pending.entry.pdf.fileName
        #endif
    }

    /// Reads the PDF off the main actor; coordinated, so a file in iCloud Drive is downloaded.
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
