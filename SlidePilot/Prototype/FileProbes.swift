import CryptoKit
import Foundation

// PROTOTYPE (issue #9). Debug output in English only, not localized. Never merged into main.

/// Outcome of one probe. Details never contain paths or file names other than the
/// placeholders `<pdf>` and `<folder>`, so a report can be shared without personal data.
nonisolated struct ProbeResult: Sendable, Identifiable {
    enum Outcome: Sendable { case ok, failed, notApplicable }

    let id = UUID()
    let name: String
    let outcome: Outcome
    let detail: String
}

/// Which grant the probes ran under.
nonisolated enum AccessContext: String, Sendable {
    case documentOnly = "document only"
    case folderGrant = "folder grant (just picked)"
    case storedFolderGrant = "folder grant (stored bookmark)"
    case storedFileBookmark = "file bookmark (after relaunch)"
}

nonisolated enum FileProbes {
    static let companionExtension = "slidepilot"

    /// Legacy notes names in the old app's search order (`AppDelegate.searchNotesDocument`).
    static func legacyNotesNames(base: String) -> [String] {
        var names: [String] = []
        for separator in ["-", "_", " "] {
            for name in ["Notes", "notes", "Notizen"] {
                names.append(base + separator + name + ".rtf")
            }
        }
        return names
    }

    /// Runs every probe for the PDF at `pdfURL`. `folderURL` is set when a folder grant is active.
    @concurrent
    static func run(pdfURL: URL, folderURL: URL?, context: AccessContext) async -> [ProbeResult] {
        var results: [ProbeResult] = []
        let folder = pdfURL.deletingLastPathComponent()
        let base = pdfURL.deletingPathExtension().lastPathComponent

        results.append(location(of: pdfURL))
        results.append(ProbeResult(name: "Access context", outcome: .notApplicable, detail: context.rawValue))

        // 1. The PDF itself, without and with an explicit security scope.
        results.append(read(pdfURL, name: "Read PDF (no explicit scope)"))
        let pdfScoped = pdfURL.startAccessingSecurityScopedResource()
        results.append(ProbeResult(name: "startAccessing(PDF)", outcome: pdfScoped ? .ok : .failed,
                                   detail: pdfScoped ? "returned true" : "returned false"))
        results.append(read(pdfURL, name: "Read PDF (scoped)"))

        var folderScoped = false
        if let folderURL {
            folderScoped = folderURL.startAccessingSecurityScopedResource()
            results.append(ProbeResult(name: "startAccessing(folder)", outcome: folderScoped ? .ok : .failed,
                                       detail: folderScoped ? "returned true" : "returned false"))
        }

        // 2. Folder listing.
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            results.append(ProbeResult(name: "List <folder>", outcome: .ok, detail: "\(items.count) items"))
        } catch {
            results.append(ProbeResult(name: "List <folder>", outcome: .failed, detail: describe(error)))
        }

        // 3. Legacy notes (NOTES-08), direct access.
        var foundLegacy: URL?
        for name in legacyNotesNames(base: base) {
            let url = folder.appending(path: name)
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard exists else { continue }
            foundLegacy = foundLegacy ?? url
            let label = "Legacy notes " + name.replacingOccurrences(of: base, with: "<pdf>")
            results.append(read(url, name: label + " (exists)"))
        }
        if foundLegacy == nil {
            results.append(ProbeResult(name: "Legacy notes", outcome: .notApplicable,
                                       detail: "fileExists false for all 9 names (absent or not visible)"))
        }

        // 4. Neighbouring files referenced by Beamer (NAV-06/07). Fixture layout: media.pdf.
        results.append(readIfPresent(folder.appending(path: "media/test-pattern.mp4"), name: "Read media/test-pattern.mp4"))
        results.append(readIfPresent(folder.appending(path: "plain-slides.pdf"), name: "Read sibling plain-slides.pdf"))

        // 5. Companion next to the PDF, written directly.
        let companion = folder.appending(path: base + "." + companionExtension)
        results.append(writeAndRemove(companion, name: "Write <pdf>.slidepilot directly"))

        // 6. Related items (macOS only): companion and legacy notes through NSFilePresenter.
        #if os(macOS)
        results.append(RelatedItemProbe.write(companion, primary: pdfURL, name: "Write <pdf>.slidepilot as related item"))
        if let foundLegacy {
            results.append(RelatedItemProbe.read(foundLegacy, primary: pdfURL, name: "Read legacy notes as related item"))
        }
        #else
        results.append(ProbeResult(name: "Related items", outcome: .notApplicable, detail: "macOS only"))
        #endif

        // 7. Companion in the app container, keyed by the PDF's path.
        results.append(containerCompanion(for: pdfURL))
        results.append(identity(of: pdfURL))

        // 8. Bookmark of the PDF.
        results.append(bookmark(pdfURL, name: "Bookmark PDF"))
        if let folderURL {
            results.append(bookmark(folderURL, name: "Bookmark <folder>"))
        }

        if folderScoped, let folderURL { folderURL.stopAccessingSecurityScopedResource() }
        if pdfScoped { pdfURL.stopAccessingSecurityScopedResource() }
        return results
    }

    // MARK: - Single probes

    static func read(_ url: URL, name: String) -> ProbeResult {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 4096) ?? Data()
            return ProbeResult(name: name, outcome: .ok, detail: "read \(data.count) bytes")
        } catch {
            return ProbeResult(name: name, outcome: .failed, detail: describe(error))
        }
    }

    static func readIfPresent(_ url: URL, name: String) -> ProbeResult {
        // fileExists can be false only because the sandbox hides the file, so try to read anyway.
        let exists = FileManager.default.fileExists(atPath: url.path)
        let result = read(url, name: name)
        return ProbeResult(name: name, outcome: result.outcome, detail: "fileExists \(exists); " + result.detail)
    }

    static func writeAndRemove(_ url: URL, name: String) -> ProbeResult {
        let alreadyThere = FileManager.default.fileExists(atPath: url.path)
        do {
            try Data("probe".utf8).write(to: url, options: .atomic)
        } catch {
            return ProbeResult(name: name, outcome: .failed, detail: describe(error))
        }
        guard !alreadyThere else {
            return ProbeResult(name: name, outcome: .ok, detail: "written (file existed before, kept)")
        }
        do {
            try FileManager.default.removeItem(at: url)
            return ProbeResult(name: name, outcome: .ok, detail: "written and removed")
        } catch {
            return ProbeResult(name: name, outcome: .ok, detail: "written, remove failed: " + describe(error))
        }
    }

    static func containerCompanion(for pdfURL: URL) -> ProbeResult {
        let name = "Write companion in app container"
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let directory = support.appending(path: "Companions", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: Data(pdfURL.standardizedFileURL.path.utf8))
            let key = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
            let url = directory.appending(path: key + "." + companionExtension)
            try Data("probe".utf8).write(to: url, options: .atomic)
            return ProbeResult(name: name, outcome: .ok, detail: "written (key from path)")
        } catch {
            return ProbeResult(name: name, outcome: .failed, detail: describe(error))
        }
    }

    /// File identity that could key a container companion and survive renames or recompiles.
    static func identity(of url: URL) -> ProbeResult {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .documentIdentifierKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return ProbeResult(name: "File identity", outcome: .failed, detail: "resource values unavailable")
        }
        let hasResourceID = values.fileResourceIdentifier != nil
        let documentID = values.documentIdentifier.map { "documentIdentifier \($0)" } ?? "no documentIdentifier"
        return ProbeResult(name: "File identity", outcome: .notApplicable,
                           detail: "fileResourceIdentifier \(hasResourceID ? "present" : "missing"); \(documentID)")
    }

    static func bookmark(_ url: URL, name: String) -> ProbeResult {
        do {
            let data = try url.bookmarkData(options: GrantStore.creationOptions,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            return ProbeResult(name: name, outcome: .ok, detail: "\(data.count) bytes")
        } catch {
            return ProbeResult(name: name, outcome: .failed, detail: describe(error))
        }
    }

    static func location(of url: URL) -> ProbeResult {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .volumeIsLocalKey, .volumeIsRemovableKey,
                                         .volumeIsInternalKey]
        let values = try? url.resourceValues(forKeys: keys)
        var parts: [String] = []
        if values?.isUbiquitousItem == true { parts.append("iCloud Drive") }
        if url.path.contains("/File Provider Storage/") { parts.append("On My iPad") }
        if url.path.contains("/Library/CloudStorage/") { parts.append("File Provider (Mac)") }
        if values?.volumeIsRemovable == true { parts.append("removable volume") }
        if values?.volumeIsLocal == false { parts.append("network volume") }
        if values?.volumeIsInternal == true { parts.append("internal volume") }
        return ProbeResult(name: "Location", outcome: .notApplicable,
                           detail: parts.isEmpty ? "unknown" : parts.joined(separator: ", "))
    }

    /// Error description without paths: domain and code plus the underlying POSIX error if any.
    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (\(underlying.domain) \(underlying.code))"
        }
        return text
    }
}

#if os(macOS)
/// Related-item access: the sandbox lets an app open `<name>.<other extension>` next to a document
/// it may access, if the other type is declared with `NSIsRelatedItemType`.
nonisolated enum RelatedItemProbe {
    final class Presenter: NSObject, NSFilePresenter {
        let primaryPresentedItemURL: URL?
        let presentedItemURL: URL?
        let presentedItemOperationQueue = OperationQueue()

        init(item: URL, primary: URL) {
            presentedItemURL = item
            primaryPresentedItemURL = primary
        }
    }

    static func write(_ url: URL, primary: URL, name: String) -> ProbeResult {
        coordinate(url, primary: primary, name: name, writing: true)
    }

    static func read(_ url: URL, primary: URL, name: String) -> ProbeResult {
        coordinate(url, primary: primary, name: name, writing: false)
    }

    private static func coordinate(_ url: URL, primary: URL, name: String, writing: Bool) -> ProbeResult {
        let presenter = Presenter(item: url, primary: primary)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinationError: NSError?
        var result = ProbeResult(name: name, outcome: .failed, detail: "accessor not called")
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                result = FileProbes.writeAndRemove(target, name: name)
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
                result = FileProbes.read(target, name: name)
            }
        }
        if let coordinationError {
            return ProbeResult(name: name, outcome: .failed, detail: "coordination: " + FileProbes.describe(coordinationError))
        }
        return result
    }
}
#endif
