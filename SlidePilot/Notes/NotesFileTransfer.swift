import SlidePilotCore
import SlidePilotRendering
import SwiftUI
import UniformTypeIdentifiers

extension FolderAccessStore {
    /// The folders the user allowed the app to read (ADR 0012), shared by all windows.
    static let app = FolderAccessStore(settings: UserDefaults.standard)
}

/// Import Notes… and Export Notes… of the focused presenter window (NOTES-06).
struct FocusedNotesFile {
    let importNotes: () -> Void
    let exportNotes: () -> Void
}

extension FocusedValues {
    @Entry var notesFile: FocusedNotesFile?
}

/// File ▸ Import Notes… (⇧⌘O) and Export Notes… (⇧⌘E), the old Open and Save Notes
/// (NOTES-06). Notes are saved automatically, so Save became an RTF export; ⌘S is not
/// used, so a habitual save does not open a save panel.
struct NotesFileCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .importExport) {
            NotesFileMenuItems()
        }
    }
}

private struct NotesFileMenuItems: View {
    @FocusedValue(\.notesFile) private var notesFile

    var body: some View {
        Button("Import Notes…") { notesFile?.importNotes() }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(notesFile == nil)
        Button("Export Notes…") { notesFile?.exportNotes() }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(notesFile == nil)
    }
}

extension View {
    /// Imports and exports the notes as legacy RTF files (NOTES-06, NOTES-09) and loads a
    /// legacy notes file next to the PDF when it opens (NOTES-08).
    func notesFileTransfer(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(NotesFileTransferModifier(session: session, fileURL: fileURL))
    }
}

/// An RTF notes file for the export panel.
private struct RTFNotesFile: FileDocument {
    static let readableContentTypes: [UTType] = [.rtf]
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

private struct NotesFileTransferModifier: ViewModifier {
    let session: PresentationSession
    let fileURL: URL?

    /// What the open panel picks: a notes file, or the folder of a legacy notes file.
    private enum Picking: Equatable {
        case notesFile
        case folder(of: URL)
    }

    private struct Failure {
        let title: LocalizedStringKey
        let message: Text
    }

    /// Imported notes waiting for the user to confirm that they replace the current ones.
    private struct PendingImport: Identifiable {
        let id = UUID()
        let notes: CompanionNotes
    }

    /// What the open panel picks; kept after it closes, because SwiftUI resets the
    /// presentation before it calls the completion handler.
    @State private var picking = Picking.notesFile
    @State private var isPicking = false
    @State private var exportFile: RTFNotesFile?
    @State private var legacyNotesFile: URL?
    @State private var pendingImport: PendingImport?
    @State private var failure: Failure?

    private var companion: DocumentCompanion { session.companion }
    private var pageCount: Int { session.cache.info.pageCount }

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.notesFile, session.notes.isAvailable ? FocusedNotesFile(
                importNotes: { pick(.notesFile) },
                exportNotes: { Task { await export() } }
            ) : nil)
            #if os(iOS)
            // The iPad menu bar is hidden until it is pulled down, so the commands are also
            // in the toolbar's overflow menu.
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button("Import Notes…", systemImage: "square.and.arrow.down") { pick(.notesFile) }
                    Button("Export Notes…", systemImage: "square.and.arrow.up") { Task { await export() } }
                }
            }
            #endif
            // The unstructured tasks below are short and stay on the main actor; a result that
            // arrives after the window closed is dropped by the checks in `importNotes`.
            // One importer for both cases: two importers on the same view would not both work.
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: picking == .notesFile ? [.rtf] : [.folder]
            ) { result in
                guard case .success(let url) = result else { return }
                switch picking {
                case .notesFile:
                    Task { await importNotes(from: url, accessing: url) }
                case .folder(let notesFile):
                    Task { await grantFolder(url, for: notesFile) }
                }
            }
            .fileDialogDefaultDirectory(defaultDirectory)
            #if os(macOS)
            .fileDialogMessage(dialogMessage)
            #endif
            .fileDialogConfirmationLabel(dialogConfirmationLabel)
            .fileExporter(
                isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                document: exportFile,
                contentType: .rtf,
                defaultFilename: exportName
            ) { result in
                if case .failure(let error) = result, !error.isUserCancellation {
                    failure = Failure(
                        title: "The Notes Couldn’t Be Exported",
                        message: Text(error.localizedDescription)
                    )
                }
            }
            // NOTES-08: offer a legacy notes file found next to the PDF once its entry is loaded.
            .task(id: companion.entry?.id) {
                await loadLegacyNotes()
            }
            .alert(
                Text("Import Notes for This PDF?"),
                isPresented: Binding(get: { legacyNotesFile != nil }, set: { if !$0 { legacyNotesFile = nil } }),
                presenting: legacyNotesFile
            ) { notesFile in
                Button("Allow Access…") {
                    pick(.folder(of: notesFile))
                }
                Button("Don’t Import", role: .cancel) {
                    companion.updateSettings { $0.declinedLegacyNotes = true }
                }
            } message: { notesFile in
                Text("SlidePilot found the notes file “\(notesFile.lastPathComponent)” next to this PDF. To import it, allow SlidePilot to read the PDF’s folder. You only need to do this once per folder. Import Notes… in the File menu stays available.")
            }
            .alert(
                Text("Replace the Notes of This PDF?"),
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                presenting: pendingImport
            ) { pending in
                Button("Replace Notes", role: .destructive) {
                    apply(pending.notes)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The imported notes replace the current notes of every slide.")
            }
            .alert(
                failure.map { Text($0.title) } ?? Text(verbatim: ""),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK") {}
            } message: { failure in
                failure.message
            }
    }

    // MARK: - Open panel

    private func pick(_ target: Picking) {
        picking = target
        isPicking = true
    }

    private var defaultDirectory: URL? {
        if case .folder(let notesFile) = picking {
            return notesFile.deletingLastPathComponent()
        }
        return fileURL?.deletingLastPathComponent()
    }

    private var dialogMessage: Text {
        if case .folder(let notesFile) = picking {
            return Text("Allow SlidePilot to read the folder that contains “\(notesFile.lastPathComponent)”.")
        }
        return Text("Choose a SlidePilot notes file in RTF format.")
    }

    private var dialogConfirmationLabel: Text {
        if case .folder = picking {
            return Text("Allow Access")
        }
        return Text("Import")
    }

    // MARK: - Import

    /// Loads the legacy notes file next to the PDF if the PDF has no notes yet (NOTES-08).
    /// The app sees the file on macOS; on iPadOS only after a folder grant.
    private func loadLegacyNotes() async {
        guard let fileURL, companion.entry != nil else { return }
        let notesFile = LegacyNotesFileName.firstExisting(forPDFAt: fileURL) {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        let action = LegacyNotesAutoLoad.action(
            notesFile: notesFile,
            hasNotes: !(companion.notes?.isEmpty ?? true),
            declined: companion.settings.declinedLegacyNotes == true,
            grantedFolder: notesFile.flatMap { FolderAccessStore.app.grantedFolder(containing: $0) }
        )
        switch action {
        case .none:
            break
        case .load(let file, let folder):
            await importNotes(from: file, accessing: folder, isAutoLoad: true)
        case .askForFolder(let file):
            legacyNotesFile = file
        }
    }

    /// Stores the folder grant the user gave in the open panel and loads the notes file.
    private func grantFolder(_ folder: URL, for notesFile: URL) async {
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { folder.stopAccessingSecurityScopedResource() }
        }
        guard FolderAccessStore.folderContains(folder, notesFile) else {
            failure = Failure(
                title: "The Notes Couldn’t Be Imported",
                message: Text("Choose the folder that contains “\(notesFile.lastPathComponent)”.")
            )
            return
        }
        // Without a bookmark the access still lasts until the app quits.
        try? FolderAccessStore.app.addGrant(for: folder)
        await importNotes(from: notesFile, accessing: folder, isAutoLoad: true)
    }

    /// Reads a legacy notes file. Notes that are not empty are only replaced after the user
    /// confirms; on failure the current notes stay (DEF-11).
    /// A file that fails to load on open is not tried again for this PDF, so the error shows
    /// once and not on every open; Import Notes… stays available.
    private func importNotes(from file: URL, accessing scope: URL, isAutoLoad: Bool = false) async {
        let entryID = companion.entry?.id
        do {
            let notes = try await Self.readNotes(from: file, accessing: scope, pageCount: pageCount)
            // The window may have closed, or another entry's data been taken over (NOTES-12),
            // while the file was read.
            guard !Task.isCancelled, companion.entry?.id == entryID, session.notes.isAvailable else { return }
            if companion.notes?.isEmpty ?? true {
                apply(notes)
            } else {
                pendingImport = PendingImport(notes: notes)
            }
        } catch is LegacyNotesRTFError {
            if isAutoLoad {
                companion.updateSettings { $0.declinedLegacyNotes = true }
            }
            failure = Failure(
                title: "The Notes Couldn’t Be Imported",
                message: Text("“\(file.lastPathComponent)” is not a SlidePilot notes file in RTF format.")
            )
        } catch {
            // Reading failed (no access, a download that failed): the format is not the cause.
            // Not marked as declined: the next open may succeed.
            failure = Failure(title: "The Notes Couldn’t Be Imported", message: Text(error.localizedDescription))
        }
    }

    /// Shows the imported notes, like the old app did after loading a notes file (NOTES-08).
    private func apply(_ notes: CompanionNotes) {
        guard session.notes.isAvailable else { return }
        session.notes.finishEditing()
        companion.setNotes(notes)
        session.layout.setVisible(.notes, true)
    }

    /// Reads and parses off the main actor: large RTF files take a noticeable time.
    @concurrent
    private static func readNotes(from file: URL, accessing scope: URL, pageCount: Int) async throws -> CompanionNotes {
        let isAccessing = scope.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { scope.stopAccessingSecurityScopedResource() }
        }
        let data = try readCoordinated(file)
        return try LegacyNotesTransfer.notes(fromLegacyRTF: data, pageCount: pageCount)
    }

    /// Coordinated, so a file in iCloud Drive is downloaded first.
    nonisolated private static func readCoordinated(_ file: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: file, options: .withoutChanges, error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try result.get()
    }

    // MARK: - Export

    private var exportName: String {
        LegacyNotesFileName.exportName(
            forPDFBaseName: fileURL?.deletingPathExtension().lastPathComponent,
            localizedNotes: String(
                localized: "NotesFileNameSuffix",
                defaultValue: "Notes",
                comment: "Suffix of the suggested notes file name: <pdf>-Notes.rtf"
            )
        )
    }

    /// Writes the notes as a legacy RTF file, one page per slide (NOTES-06).
    private func export() async {
        session.notes.finishEditing()
        let notes = companion.notes
        let pageCount = pageCount
        do {
            exportFile = RTFNotesFile(data: try await Self.rtf(from: notes, pageCount: pageCount))
        } catch {
            failure = Failure(
                title: "The Notes Couldn’t Be Exported",
                message: Text("SlidePilot couldn’t convert the notes to RTF.")
            )
        }
    }

    @concurrent
    private static func rtf(from notes: CompanionNotes?, pageCount: Int) async throws -> Data {
        try LegacyNotesTransfer.legacyRTF(from: notes, pageCount: pageCount)
    }
}

private extension Error {
    var isUserCancellation: Bool {
        (self as? CocoaError)?.code == .userCancelled
    }
}
