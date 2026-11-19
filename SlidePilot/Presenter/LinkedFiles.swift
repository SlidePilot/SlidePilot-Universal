import AVFoundation
import Foundation
import Observation
import SlidePilotCore
import SlidePilotRendering
import UniformTypeIdentifiers
import os

nonisolated let linkedFilesLog = Logger(subsystem: "SlidePilot", category: "LinkedFiles")

/// The videos (`\movie`, NAV-07) and `run:` link targets (NAV-06) of one document, and the
/// folder access they need (ADR 0012).
///
/// Owned by the session. The presenter and the presentation get the same player for a
/// video, so playback is mirrored like in the old app (`ConnectedPlayer.sharedPlayers`).
@Observable
final class LinkedFiles {
    /// A problem with a `run:` link, shown in an alert.
    enum Problem: Identifiable, Equatable {
        case notFound(String)
        case refused(String)

        var id: String {
            switch self {
            case .notFound(let name): "notFound-\(name)"
            case .refused(let name): "refused-\(name)"
            }
        }
    }

    /// The opened PDF; references are resolved against it. `nil` when the document system
    /// gives no URL; then only web videos play.
    private(set) var documentURL: URL?
    /// Some referenced file next to the PDF cannot be read yet: the folder grant is missing.
    private(set) var needsFolderAccess = false
    /// Asks the user for the folder (alert, then the folder picker).
    var isAskingForFolderAccess = false
    var isPickingFolder = false
    /// A `run:` target to show in Quick Look (iPad).
    var previewURL: URL?
    var problem: Problem?

    @ObservationIgnored private let folderStore: FolderAccessStore?
    @ObservationIgnored private var accessedFolders: [URL] = []
    @ObservationIgnored private var players: [URL: AVPlayer] = [:]
    @ObservationIgnored private var activePage: Int?
    @ObservationIgnored private var hasAsked = false
    /// Changes whenever access was granted, so views check their files again.
    private(set) var accessGeneration = 0

    init(folderStore: FolderAccessStore?) {
        self.folderStore = folderStore
    }

    isolated deinit {
        for player in players.values { player.pause() }
        stopAccessingFolders()
    }

    // MARK: - Document

    /// Reads which files the PDF refers to and asks for folder access once per opened
    /// document when one of them is next to the PDF but not readable.
    func prepare(documentURL: URL?, cache: RenderCache) async {
        self.documentURL = documentURL
        guard let documentURL else { return }
        let references = await cache.linkedFileReferences()
        guard !Task.isCancelled else { return }
        let files = references.compactMap { LinkedFile.resolve($0, relativeTo: documentURL) }.filter(\.isFileURL)
        startAccessingGrantedFolders(for: files + [documentURL])
        needsFolderAccess = files.contains { !Self.isReadable($0) && LinkedFileSystem.mayExist($0) }
        if needsFolderAccess, !hasAsked {
            hasAsked = true
            isAskingForFolderAccess = true
        }
    }

    /// The PDF's folder, where the folder picker starts.
    var documentFolder: URL? { documentURL?.deletingLastPathComponent() }

    func requestFolderAccess() {
        isPickingFolder = true
    }

    /// Keeps the folder the user picked and reads the files again.
    func grantAccess(to folder: URL) {
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        do {
            try folderStore?.addGrant(for: folder)
        } catch {
            linkedFilesLog.error("Folder grant failed: \(error.localizedDescription, privacy: .public)")
        }
        if let documentURL {
            stopAccessingFolders()
            startAccessingGrantedFolders(for: [documentURL])
            if accessedFolders.isEmpty, folder.startAccessingSecurityScopedResource() {
                // Without a store (previews) the picked folder is used for this session.
                accessedFolders.append(folder)
            }
        }
        needsFolderAccess = false
        accessGeneration += 1
    }

    // MARK: - Files

    /// The URL of a reference in the PDF, or `nil` if it names nothing usable.
    func url(for reference: String) -> URL? {
        guard let documentURL else {
            return URL(string: reference).flatMap { $0.scheme == "http" || $0.scheme == "https" ? $0 : nil }
        }
        return LinkedFile.resolve(reference, relativeTo: documentURL)
    }

    /// Whether a video at `url` can be played now. Web videos always try.
    func isAvailable(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        startAccessingGrantedFolders(for: [url])
        return Self.isReadable(url)
    }

    // MARK: - Players

    /// The shared player for a video on `page`. A new page stops and drops the players of
    /// the previous one, like the old app did when the slide changed.
    func player(for url: URL, page: Int) -> AVPlayer {
        showPage(page)
        if let player = players[url] { return player }
        let player = AVPlayer(url: url)
        players[url] = player
        return player
    }

    func showPage(_ page: Int) {
        guard page != activePage else { return }
        activePage = page
        for player in players.values { player.pause() }
        players.removeAll()
    }

    // MARK: - Run links

    /// Opens the target of a `run:` link (NAV-06): documents in their default app (Mac) or
    /// in Quick Look (iPad). Programs and scripts are refused.
    func open(_ reference: String) {
        guard let url = url(for: reference) else {
            problem = .notFound(reference)
            return
        }
        guard url.isFileURL else {
            LinkedFileSystem.open(url, in: self)
            return
        }
        startAccessingGrantedFolders(for: [url])
        guard Self.isReadable(url) else {
            if LinkedFileSystem.mayExist(url), documentURL != nil, folderStore?.grantedFolder(containing: url) == nil {
                isAskingForFolderAccess = true
            } else {
                problem = .notFound(url.lastPathComponent)
            }
            return
        }
        guard RunLinkPolicy.allowsOpening(Self.contentType(of: url), fileExtension: url.pathExtension) else {
            problem = .refused(url.lastPathComponent)
            return
        }
        LinkedFileSystem.open(url, in: self)
    }

    // MARK: - Private

    private func startAccessingGrantedFolders(for files: [URL]) {
        guard let folderStore else { return }
        for file in files where !accessedFolders.contains(where: { Self.isInside(file, $0) }) {
            guard let folder = folderStore.grantedFolder(containing: file) else { continue }
            if folder.startAccessingSecurityScopedResource() {
                accessedFolders.append(folder)
            }
        }
    }

    private func stopAccessingFolders() {
        for folder in accessedFolders { folder.stopAccessingSecurityScopedResource() }
        accessedFolders.removeAll()
    }

    /// A cheap pre-check before asking the store; the store decides by file identity.
    private static func isInside(_ file: URL, _ folder: URL) -> Bool {
        file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    /// Opening the file, not `isReadableFile`, tells whether the sandbox lets the app read it.
    private static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }

    private static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
    }
}
