import Foundation
import SlidePilotRendering
import UniformTypeIdentifiers
import SwiftUI

// PROTOTYPE (issue #10). Never merged into main.

/// Read-only PDF document. Records what the document system delivered, so the probe can
/// see whether DocumentGroup itself re-reads the file after a change on disk.
nonisolated struct ReloadProbeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    let data: Data
    let digest: String
    let deliveredAt: Date

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        digest = ReloadPipeline.digest(data)
        deliveredAt = Date()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
