#if os(macOS)
import AppKit

/// Mac part of `LinkedFiles`.
enum LinkedFileSystem {
    /// The Mac sandbox shows whether a file next to the PDF exists, even without access.
    static func mayExist(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Opens a `run:` target in its default app (NAV-06), like the old app (`NSWorkspace`).
    static func open(_ url: URL, in files: LinkedFiles) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error {
                linkedFilesLog.error("Opening a run: link failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
