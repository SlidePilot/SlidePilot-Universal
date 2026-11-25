import CryptoKit
import Foundation

/// Temporary files for videos stored inside a PDF (NAV-07, #142).
///
/// AVFoundation plays files, not bytes, so an embedded video is written to a file of its
/// own, inside the app's temporary folder. One store belongs to one opened document and
/// keeps its files in a folder of its own, which it removes when the document closes (the
/// store is released). A file is named after its content, so the presenter, the
/// presentation, overlay build steps and the versions of a reloaded PDF that embed the
/// same video share one URL and therefore one player.
public actor EmbeddedFileStore {
    /// The folder of all stores, inside the app's temporary folder.
    public static let defaultParent = FileManager.default.temporaryDirectory
        .appending(path: "Embedded Videos", directoryHint: .isDirectory)

    /// This store's folder; created with the first file.
    public nonisolated let directory: URL
    private var written: Set<URL> = []
    /// When each file was last asked for, counted in requests.
    private var lastRequest: [URL: Int] = [:]
    private var requests = 0

    public init(parent: URL = EmbeddedFileStore.defaultParent) {
        directory = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    // The folder must go with the document, also when nobody awaits a cleanup.
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The file holding `data`, written on the first request. `fileExtension` tells
    /// AVFoundation the type of the video; it is reduced to letters and digits.
    public func file(for data: Data, fileExtension: String) throws -> URL {
        let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        let safeExtension = String(fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8))
        let url = safeExtension.isEmpty
            ? directory.appending(path: digest, directoryHint: .notDirectory)
            : directory.appending(path: "\(digest).\(safeExtension)", directoryHint: .notDirectory)
        requests += 1
        lastRequest[url] = requests
        if written.contains(url), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return url
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        written.insert(url)
        return url
    }

    /// The files written so far.
    public var files: Set<URL> { written }

    /// A point in the order of requests, for `removeAll(except:requestedSince:)`.
    public func mark() -> Int { requests }

    /// Removes every file but `kept`, for example after a reload of the PDF that no longer
    /// embeds a video. With `mark`, a file asked for after it stays too: a newer reload may
    /// use it while an older one decides what to remove.
    public func removeAll(except kept: Set<URL>, requestedSince mark: Int? = nil) {
        for url in written.subtracting(kept) {
            if let mark, lastRequest[url, default: 0] > mark { continue }
            try? FileManager.default.removeItem(at: url)
            written.remove(url)
            lastRequest[url] = nil
        }
    }

    /// Removes every file and the folder, when the document closes. A file asked for
    /// later is written again.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        written.removeAll()
        lastRequest.removeAll()
    }

    /// Removes the folders that stores left behind when the app ended without closing its
    /// documents. Call at launch, before any document opens.
    public static func removeLeftovers(in parent: URL = EmbeddedFileStore.defaultParent) {
        try? FileManager.default.removeItem(at: parent)
    }
}
