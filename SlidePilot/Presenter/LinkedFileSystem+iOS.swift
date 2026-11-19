#if os(iOS)
import UIKit

/// iPad part of `LinkedFiles`.
enum LinkedFileSystem {
    /// Without folder access iPadOS does not even show whether a file exists, so any file
    /// may be there.
    static func mayExist(_ url: URL) -> Bool {
        true
    }

    /// Shows a `run:` target in Quick Look (NAV-06); there is no default app to hand it to.
    static func open(_ url: URL, in files: LinkedFiles) {
        if url.isFileURL {
            files.previewURL = url
        } else {
            UIApplication.shared.open(url)
        }
    }
}
#endif
