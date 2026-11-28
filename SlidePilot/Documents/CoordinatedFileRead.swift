import Foundation

enum CoordinatedFileRead {
    /// Reads a file with file coordination, so a file in iCloud Drive is downloaded first.
    /// Blocks the calling thread until then: call it off the main actor. The caller starts
    /// the security scope if the file needs one.
    nonisolated static func data(at file: URL) throws -> Data {
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
}
