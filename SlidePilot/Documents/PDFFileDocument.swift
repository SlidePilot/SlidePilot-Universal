import SlidePilotRendering
import SwiftUI
import UniformTypeIdentifiers

/// A PDF opened for presenting. SlidePilot never writes the PDF (DOC-03: role Viewer).
///
/// `nonisolated` because the document system reads files off the main actor.
nonisolated struct PDFFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    let data: Data
    let info: PDFDocumentInfo

    init(configuration: ReadConfiguration) throws {
        let fileName = configuration.file.filename ?? configuration.file.preferredFilename
        guard let data = configuration.file.regularFileContents else {
            throw DocumentOpenError(fileName: fileName, reason: .notAPDF)
        }
        do {
            try self.init(data: data)
        } catch {
            throw DocumentOpenError(fileName: fileName, reason: error)
        }
    }

    init(data: Data) throws(PDFOpenError) {
        info = try PDFInspector.inspect(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

/// Shown by the system's open-error alert (DEF-17).
nonisolated struct DocumentOpenError: LocalizedError {
    let fileName: String?
    let reason: PDFOpenError

    var errorDescription: String? {
        if let fileName {
            String(localized: "The document “\(fileName)” could not be opened.")
        } else {
            String(localized: "The document could not be opened.")
        }
    }

    var recoverySuggestion: String? {
        switch reason {
        case .notAPDF:
            String(localized: "The file is damaged or is not a PDF document.")
        case .locked:
            String(localized: "The PDF is protected with a password. Remove the password and open it again.")
        case .noPages:
            String(localized: "The PDF does not contain any pages.")
        }
    }
}
