import CoreTransferable
import SlidePilotCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The `.slidepilot` file (NOTES-11, ADR 0019). Exported in Info.plist as the bundle ID
    /// plus `.slidepilot`, so no bundle ID is written here.
    nonisolated static var slidePilotFile: UTType {
        UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "SlidePilot").\(SlidePilotFileFormat.fileExtension)", conformingTo: .data)
    }
}

/// A `.slidepilot` file: opened as a document of its own (double-click, AirDrop, Open With,
/// File ▸ Open) and written by the save panel (NOTES-11).
///
/// `nonisolated` because the document system reads files off the main actor.
nonisolated struct SlidePilotFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.slidePilotFile] }

    /// A file from a later app version opens with an explanation instead of the system's
    /// generic error.
    let content: Result<SlidePilotFile, SlidePilotFileFormat.DecodingError>

    init(file: SlidePilotFile) {
        content = .success(file)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            content = .success(try SlidePilotFileFormat.decode(data))
        } catch .newerVersion {
            content = .failure(.newerVersion)
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard case .success(let file) = content else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: try SlidePilotFileFormat.encode(file))
    }
}

/// A `.slidepilot` file for the iPad share sheet (Save to Files, AirDrop, Mail). The data
/// is read when the user picks a target, so unsaved changes of an open window are included.
nonisolated struct SlidePilotFileExport: Transferable {
    let fileName: String
    let file: @Sendable () async -> SlidePilotFile?

    static var transferRepresentation: some TransferRepresentation {
        // A file, so Save to Files and AirDrop keep the suggested name.
        FileRepresentation(exportedContentType: .slidePilotFile) { item in
            guard let file = await item.file() else { throw CocoaError(.fileWriteUnknown) }
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: item.fileName, directoryHint: .notDirectory)
            try SlidePilotFileFormat.encode(file).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

extension SlidePilotFile {
    /// The suggested name `<pdf>.slidepilot` (NOTES-11).
    static func exportName(forPDFNamed fileName: String?) -> String {
        exportName(
            forPDFBaseName: fileName.map { ($0 as NSString).deletingPathExtension },
            untitled: String(localized: "Untitled")
        )
    }
}
