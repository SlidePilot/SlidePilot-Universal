import Foundation
import UniformTypeIdentifiers

/// A file that a PDF refers to: the video of a Beamer `\movie` (NAV-07) or the target of a
/// `\href{run:…}` link (NAV-06). LaTeX writes the reference as given in the source, usually
/// a path relative to the PDF.
public enum LinkedFile {
    /// The URL that `reference` names, read relative to the PDF at `pdfURL`.
    ///
    /// Web addresses (`http`, `https`) and `file` URLs are used as they are, absolute paths
    /// as file paths, anything else as a path relative to the PDF's folder. Unlike the old
    /// app (`URL(string:relativeTo:)`), paths with spaces work. Other schemes give `nil`.
    public static func resolve(_ reference: String, relativeTo pdfURL: URL) -> URL? {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }
        // A scheme has at least two characters, so a Windows drive ("C:\…") is no scheme.
        if let url = URL(string: reference), let scheme = url.scheme?.lowercased(), scheme.count > 1 {
            switch scheme {
            case "http", "https": return url
            case "file": return url.isFileURL ? url.standardizedFileURL : nil
            default: return nil
            }
        }
        if reference.hasPrefix("/") {
            return URL(filePath: reference).standardizedFileURL
        }
        return pdfURL.deletingLastPathComponent()
            .appending(path: reference, directoryHint: .notDirectory)
            .standardizedFileURL
    }
}

/// Which `run:` link targets SlidePilot opens (NAV-06).
///
/// A PDF can name any file, also a program or a script. Only documents and media are
/// opened; anything that would run code is refused (approved deviation from the old app).
public enum RunLinkPolicy {
    /// Whether a file of `type` with `fileExtension` may be opened. Unknown types are
    /// refused, and so are runnable formats that the system may not have registered.
    public static func allowsOpening(_ type: UTType?, fileExtension: String = "") -> Bool {
        guard let type, !blockedExtensions.contains(fileExtension.lowercased()) else { return false }
        return !blockedTypes.contains { type.conforms(to: $0) }
    }

    private static let blockedExtensions: Set<String> = [
        "app", "command", "tool", "workflow", "action", "terminal", "jar", "pkg", "mpkg",
        "prefpane", "kext", "scpt", "scptd", "applescript", "sh", "zsh", "bash", "csh", "py", "pl", "rb",
    ]

    private static let blockedTypes: [UTType] = [
        .executable, .application, .applicationBundle, .applicationExtension,
        .unixExecutable, .script, .shellScript, .bundle, .pluginBundle,
    ] + [
        "com.apple.installer-package-archive",
        "com.apple.automator-workflow",
        "com.apple.terminal.shell-script",
        "com.apple.applescript.script",
        "com.apple.systempreference.prefpane",
        "com.apple.mach-o-binary",
    ].compactMap { UTType($0) }
}
