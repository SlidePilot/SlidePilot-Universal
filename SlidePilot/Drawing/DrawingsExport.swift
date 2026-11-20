import CoreTransferable
import SlidePilotCore
import SlidePilotRendering
import SwiftUI
import UniformTypeIdentifiers

/// Export Drawings… of the focused presenter window (DRAW-10).
struct FocusedDrawingsExport {
    let export: () -> Void
}

extension FocusedValues {
    @Entry var drawingsExport: FocusedDrawingsExport?
}

/// File ▸ Export Drawings… (⇧⌘S), like the old app (DRAW-10): after Open Recent, before
/// Close. The document system's Duplicate also uses ⇧⌘S; AppKit gives a shortcut to the
/// first matching item, so the export must come before the save items.
struct DrawingsExportCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .saveItem) {
            DrawingsExportMenuItem()
        }
    }
}

private struct DrawingsExportMenuItem: View {
    @FocusedValue(\.drawingsExport) private var drawingsExport

    var body: some View {
        Button("Export Drawings…") { drawingsExport?.export() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(drawingsExport == nil)
    }
}

extension View {
    /// Exports a copy of the PDF with the drawings as annotations (DRAW-10).
    func drawingsExport(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(DrawingsExportModifier(session: session, fileURL: fileURL))
    }
}

/// What gets exported: the PDF on screen and the drawings at the moment of the export.
/// A value, so the export can run off the main actor and in the share sheet.
nonisolated struct DrawingsPDF: Sendable, Transferable {
    let pdf: Data
    let drawings: [Int: PageDrawing]
    let fileName: String

    func pdfData() throws -> Data {
        try DrawingsPDFExporter.export(pdf: pdf, drawings: drawings)
    }

    static var transferRepresentation: some TransferRepresentation {
        // The share sheet gets a file, so Save to Files and AirDrop keep the suggested name.
        FileRepresentation(exportedContentType: .pdf) { item in
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: item.fileName, directoryHint: .notDirectory)
            try item.pdfData().write(to: file)
            return SentTransferredFile(file)
        }
    }
}

/// A finished PDF for the save panel.
private struct ExportedPDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct DrawingsExportModifier: ViewModifier {
    let session: PresentationSession
    let fileURL: URL?

    @State private var exportFile: ExportedPDFFile?
    @State private var failureMessage: String?
    @State private var isExporting = false

    func body(content: Content) -> some View {
        content
            // A short task on the main actor; a result that arrives after the window closed
            // only sets state that is gone. A second ⇧⌘S during an export is ignored.
            .focusedSceneValue(\.drawingsExport, FocusedDrawingsExport { Task { await export() } })
            #if os(iOS)
            // The iPad menu bar is hidden until it is pulled down, so the export is also in
            // the toolbar's overflow menu, as a share sheet (Save to Files, AirDrop, Mail).
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    ShareLink(
                        item: drawingsPDF,
                        preview: SharePreview(drawingsPDF.fileName)
                    ) {
                        Label("Export Drawings…", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
            #endif
            .fileExporter(
                isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                document: exportFile,
                contentType: .pdf,
                defaultFilename: drawingsPDF.fileName
            ) { result in
                // Cancelling the save panel is not a failure (DEF-05).
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    failureMessage = error.localizedDescription
                }
            }
            .alert(
                Text("The Drawings Couldn’t Be Exported"),
                isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } }),
                presenting: failureMessage
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
    }

    private var drawingsPDF: DrawingsPDF {
        // `data` is not observed; reading the reload counter keeps the share item current
        // after the PDF was recompiled (DOC-08).
        _ = session.contentVersion
        return DrawingsPDF(
            pdf: session.data,
            drawings: session.drawing.drawings.pages,
            fileName: DrawingsPDFExporter.exportName(
                forPDFBaseName: fileURL?.deletingPathExtension().lastPathComponent,
                localizedDrawings: String(
                    localized: "DrawingsFileNameSuffix",
                    defaultValue: "Drawings",
                    comment: "Suffix of the suggested drawings file name: <pdf>-Drawings.pdf"
                )
            )
        )
    }

    /// Writes the copy off the main actor, then opens the save panel.
    private func export() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let item = drawingsPDF
        do {
            exportFile = ExportedPDFFile(data: try await Self.pdfData(of: item))
        } catch {
            failureMessage = String(localized: "SlidePilot couldn’t add the drawings to a copy of the PDF.")
        }
    }

    @concurrent
    private static func pdfData(of item: DrawingsPDF) async throws -> Data {
        try item.pdfData()
    }
}
