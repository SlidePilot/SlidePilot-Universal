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
    @ObservationIgnored private var players = SlideVideoPlayers<MoviePlayback>()
    @ObservationIgnored private var hasAsked = false
    /// Reads the shown page's videos after a step; replaced by the next page change.
    @ObservationIgnored private var settling: Task<Void, Never>?
    /// The local files the PDF refers to, checked again after a grant.
    @ObservationIgnored private var referencedFiles: [URL] = []
    /// Changes whenever access was granted, so views check their files again.
    private(set) var accessGeneration = 0

    init(folderStore: FolderAccessStore?) {
        self.folderStore = folderStore
    }

    isolated deinit {
        settling?.cancel()
        for playback in players.removeAll() { playback.stop() }
        stopAccessingFolders()
    }

    // MARK: - Document

    /// Reads which files the PDF refers to and asks for folder access once per opened
    /// document when one of them is next to the PDF but not readable.
    func prepare(documentURL: URL?, cache: RenderCache) async {
        // A moved document no longer needs the old folder.
        if documentURL != self.documentURL { stopAccessingFolders() }
        self.documentURL = documentURL
        guard let documentURL else { return }
        let references = await cache.linkedFileReferences()
        guard !Task.isCancelled else { return }
        let files = references.compactMap { LinkedFile.resolve($0, relativeTo: documentURL) }.filter(\.isFileURL)
        referencedFiles = files
        startAccessingGrantedFolders(for: files + [documentURL])
        updateNeedsFolderAccess()
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
        // A folder that does not hold the files leaves the request in place.
        startAccessingGrantedFolders(for: referencedFiles)
        updateNeedsFolderAccess()
        accessGeneration += 1
    }

    // MARK: - Files

    /// The video's file: the temporary copy of a video stored inside the PDF (#142), else
    /// the file its reference names.
    func url(for movie: SlideMovie) -> URL? {
        movie.embeddedFile ?? url(for: movie.reference)
    }

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

    /// The shared player for `movie` on `page`. A jump stops and drops the players of the
    /// previous page, like the old app did when the slide changed; a step keeps a video that
    /// the new page shows again at the same place (overlay build steps, #140).
    ///
    /// The player is set up here, not in a view, so a video that autostarts plays once
    /// although the presenter and the presentation both show it (#139). Two videos of one
    /// file on the same page share a player, so the first one's activation applies.
    func player(for movie: SlideMovie, url: URL, page: Int) -> AVPlayer {
        let video = SlideVideo(file: url, area: movie.bounds, autostarts: movie.activation.autostarts)
        let (playback, changes) = players.player(for: video, on: page) {
            MoviePlayback(url: url, activation: movie.activation)
        }
        apply(changes)
        return playback.player
    }

    /// Shows `page`. After a step, the previous page's players wait until this page's
    /// videos are read; the ones it shows again at the same place play on (#140).
    func showPage(_ page: Int, change: PageChange, cache: RenderCache) {
        for playback in players.show(page: page, change: change) { playback.stop() }
        settling?.cancel()
        settling = nil
        guard players.hasCandidates else { return }
        settling = Task { [weak self] in
            let movies = await cache.movies(page: page)
            guard !Task.isCancelled, let self else { return }
            self.apply(self.players.settle(page: page, showing: self.videos(movies)))
        }
    }

    /// After a reload (DOC-08) the current page may no longer show a video or show another
    /// file: those players stop, in every window. Videos still on the page play on (#138).
    func reloaded(page: Int, cache: RenderCache) async {
        let movies = await cache.movies(page: page)
        guard !Task.isCancelled else { return }
        // A step just before the reload settles against the new PDF, not the old one.
        settling?.cancel()
        settling = nil
        let shown = videos(movies)
        let settled = players.settle(page: page, showing: shown)
        for playback in settled.toStart { playback.start() }
        let dropped = settled.dropped + players.reloaded(page: page, showing: Set(shown.map(\.file)))
        for playback in dropped { playback.stop() }
        if !dropped.isEmpty {
            linkedFilesLog.info("Stopped \(dropped.count, privacy: .public) video(s) that a reload removed from page \(page + 1, privacy: .public)")
        }
    }

    private func videos(_ movies: [SlideMovie]) -> [SlideVideo] {
        movies.compactMap { movie in
            url(for: movie).map {
                SlideVideo(file: $0, area: movie.bounds, autostarts: movie.activation.autostarts)
            }
        }
    }

    private func apply(_ changes: SlideVideoPlayers<MoviePlayback>.Changes) {
        for playback in changes.dropped { playback.stop() }
        for playback in changes.toStart { playback.start() }
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
        // A symbolic link or alias must not smuggle a program past the policy.
        let target = ((try? URL(resolvingAliasFileAt: url)) ?? url).resolvingSymlinksInPath()
        guard RunLinkPolicy.allowsOpening(Self.contentType(of: target), fileExtension: target.pathExtension) else {
            problem = .refused(url.lastPathComponent)
            return
        }
        LinkedFileSystem.open(url, in: self)
    }

    // MARK: - Private

    private func updateNeedsFolderAccess() {
        needsFolderAccess = referencedFiles.contains { !Self.isReadable($0) && LinkedFileSystem.mayExist($0) }
    }

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
