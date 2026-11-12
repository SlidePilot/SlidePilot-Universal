import SwiftUI
import UniformTypeIdentifiers

// PROTOTYPE (issue #9). Never merged into main.

/// Read-only PDF document. The probe only needs the file URL, so the content is not kept.
nonisolated struct ProbeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    /// Size of the file as delivered by the document system, before any probe runs.
    let deliveredByteCount: Int

    init(configuration: ReadConfiguration) throws {
        deliveredByteCount = configuration.file.regularFileContents?.count ?? 0
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
