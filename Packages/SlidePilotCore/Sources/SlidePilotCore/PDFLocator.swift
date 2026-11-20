import Foundation
import os

/// Problems with the companion file; they never reach the user, so they are logged.
let companionLog = Logger(subsystem: "SlidePilot", category: "CompanionFile")

/// A bookmark resolved to the file it points to now.
public struct ResolvedBookmark: Sendable, Equatable {
    public var url: URL
    /// The file was replaced (e.g. a LaTeX recompile with an atomic save) or moved; the
    /// bookmark still found it but should be created again (ADR 0013).
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

/// Finds PDFs again across launches, renames and moves (ADR 0012). Injected into
/// `CompanionStore` so tests can run without real bookmarks.
public protocol PDFLocator: Sendable {
    func bookmark(for url: URL) throws -> Data
    /// `nil` when the PDF is not found (deleted, on another volume that is not mounted).
    func resolve(_ bookmark: Data) -> ResolvedBookmark?
    /// Whether both URLs name the same file. Compares file identity, not path strings,
    /// because the same file can show up under different paths (ADR 0012).
    func isSameFile(_ first: URL, _ second: URL) -> Bool
    /// The system's persistent document identifier (iPadOS file providers), if any.
    func documentIdentifier(of url: URL) -> Int?
    /// Where the bookmark last saw its PDF, without looking for it; also for a PDF that is
    /// not found. Used to tell PDFs with the same name apart (SET-07).
    func lastKnownURL(of bookmark: Data) -> URL?
}

extension PDFLocator {
    public func lastKnownURL(of bookmark: Data) -> URL? { nil }
}

/// `PDFLocator` with Foundation bookmarks: security-scoped on macOS (the app sandbox needs
/// that to see the file again later), plain on iPadOS, where every bookmark carries its scope.
public struct FileBookmarkLocator: PDFLocator {
    public init() {}

    #if os(macOS)
    // The app only reads PDFs (viewer documents), so a read-only scope is enough; a PDF opened
    // read-only gets no security-scoped bookmark without `securityScopeAllowOnlyReadAccess`.
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI, .withoutMounting]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
    #endif

    public func bookmark(for url: URL) throws -> Data {
        try withAccess(to: url) {
            do {
                return try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                // A plain bookmark still finds the file again for matching; only reading
                // through it later would need the scope.
                companionLog.error("Security-scoped bookmark failed: \(error.localizedDescription, privacy: .public)")
                return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
        }
    }

    public func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        var isStale = false
        // Plain bookmarks from the fallback in `bookmark(for:)` resolve without the scope option.
        guard let url = (try? URL(resolvingBookmarkData: bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale))
            ?? (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale))
        else { return nil }
        // A bookmark can resolve to the last known path of a file that is gone.
        let exists = withAccess(to: url) { (try? url.checkResourceIsReachable()) ?? false }
        return exists ? ResolvedBookmark(url: url, isStale: isStale) : nil
    }

    public func isSameFile(_ first: URL, _ second: URL) -> Bool {
        if let firstID = identifier(of: first), let secondID = identifier(of: second) {
            return firstID.isEqual(secondID)
        }
        return first.standardizedFileURL.resolvingSymlinksInPath() == second.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func documentIdentifier(of url: URL) -> Int? {
        withAccess(to: url) { try? url.resourceValues(forKeys: [.documentIdentifierKey]).documentIdentifier }
    }

    public func lastKnownURL(of bookmark: Data) -> URL? {
        guard let path = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path else { return nil }
        return URL(filePath: path)
    }

    private func identifier(of url: URL) -> (any NSObjectProtocol)? {
        // A resolved bookmark can carry the cached identifier of a file that a recompile
        // replaced since (seen on iPadOS), so the value is read fresh.
        var url = url
        url.removeAllCachedResourceValues()
        return withAccess(to: url) { [url] in try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier }
    }

    private func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }
}
