import AppKit
import Security

// Every rule that keeps the test host from seeing or touching anything except
// the SlidePilot test build lives in this file (ADR 0018). Review changes here
// with care: the Screen Recording and Accessibility grants are bound to the
// exact binary, so any change needs a new grant by the maintainer.

enum PolicyError: Error, CustomStringConvertible {
    case refused(String)
    var description: String {
        switch self {
        case .refused(let reason): "Refused: \(reason)"
        }
    }
}

/// A running SlidePilot test build that passed every identity check.
struct VerifiedTarget {
    let app: NSRunningApplication
    var pid: pid_t { app.processIdentifier }
}

@MainActor
enum Policy {
    /// The only app the host captures or controls. It comes from the host's own
    /// Info.plist, which is sealed by the code signature.
    static let targetBundleID: String = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "SPTargetBundleIdentifier") as? String,
              id.hasSuffix(".SlidePilot.testhost") else {
            fatalError("SPTargetBundleIdentifier missing or not a SlidePilot test build ID")
        }
        return id
    }()

    /// Entitlements the target may have. Anything else (file access, temporary
    /// exceptions, contacts, camera, …) could show personal data, so it is refused.
    static let allowedEntitlements: Set<String> = [
        "com.apple.security.app-sandbox",
        "com.apple.security.get-task-allow",
        "com.apple.security.network.client",
        "com.apple.security.network.server",
    ]

    // MARK: Target identity

    /// Checks an app bundle before the host launches it.
    static func verifyBundle(at url: URL) throws {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == targetBundleID else {
            throw PolicyError.refused("\(url.lastPathComponent) is not the SlidePilot test build (\(targetBundleID))")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw PolicyError.refused("cannot read the code signature")
        }
        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckNestedCode), nil) == errSecSuccess else {
            throw PolicyError.refused("the code signature is not valid")
        }
        try checkSigningInfo(of: staticCode)
    }

    /// Finds the running test build and checks it again (it may have been
    /// replaced or restarted since the last command).
    static func currentTarget() throws -> VerifiedTarget {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
            .filter { !$0.isTerminated }
        guard running.count == 1, let app = running.first else {
            throw PolicyError.refused(running.isEmpty
                ? "the SlidePilot test build is not running (use launch)"
                : "more than one SlidePilot test build is running")
        }
        let attributes = [kSecGuestAttributePid: app.processIdentifier] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            throw PolicyError.refused("cannot read the running app's code signature")
        }
        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else {
            throw PolicyError.refused("the running app's code signature is not valid")
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw PolicyError.refused("cannot read the running app's code")
        }
        try checkSigningInfo(of: staticCode)
        return VerifiedTarget(app: app)
    }

    private static func checkSigningInfo(of code: SecStaticCode) throws {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else {
            throw PolicyError.refused("cannot read the signing information")
        }
        guard info[kSecCodeInfoIdentifier as String] as? String == targetBundleID else {
            throw PolicyError.refused("the signing identifier is not \(targetBundleID)")
        }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        guard entitlements["com.apple.security.app-sandbox"] as? Bool == true else {
            throw PolicyError.refused("the app does not run in the App Sandbox")
        }
        let extra = Set(entitlements.keys).subtracting(allowedEntitlements)
        guard extra.isEmpty else {
            throw PolicyError.refused("entitlements not allowed for the test build: \(extra.sorted().joined(separator: ", "))")
        }
    }

    // MARK: Files

    /// Output and document names are plain file names, never paths.
    static func checkedFileName(_ name: String, extensions: Set<String>) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix("."),
              name.unicodeScalars.allSatisfy(allowed.contains),
              extensions.contains((name as NSString).pathExtension.lowercased()) else {
            throw PolicyError.refused("invalid file name \(name)")
        }
        return name
    }

    /// A document must be a regular file directly inside the inbox, which only
    /// Claude's sandboxed shell fills (it cannot read personal folders). Symbolic
    /// links are refused, so nothing outside the inbox can be opened.
    static func inboxDocument(_ name: String, inbox: URL) throws -> URL {
        let file = try checkedFileName(name, extensions: ["pdf", "slidepilot"])
        let url = inbox.appendingPathComponent(file)
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
            throw PolicyError.refused("\(file) is not a regular file in the inbox")
        }
        return url
    }

    // MARK: Input

    /// Menu items that could bring data from outside the test build into its
    /// windows (clipboard, contacts, files, other apps). Titles are English,
    /// because the host launches the test build in English.
    static let blockedMenuTitles: Set<String> = [
        "paste", "paste and match style", "paste style", "paste and preserve formatting",
        "autofill", "contact", "passwords", "credit card",
        "services", "open", "open recent", "share", "start dictation",
        "print", "page setup", "import", "import from iphone or ipad",
    ]

    static func isBlockedMenuTitle(_ title: String) -> Bool {
        var normalized = title.lowercased().trimmingCharacters(in: .whitespaces)
        for suffix in ["…", "..."] where normalized.hasSuffix(suffix) {
            normalized = String(normalized.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return blockedMenuTitles.contains(normalized) || normalized.hasPrefix("paste")
            || normalized.hasPrefix("autofill") || normalized.hasPrefix("import")
    }

    /// AppKit gives standard menu items language-independent identifiers (the
    /// action selector, e.g. "paste:", or "_NSMenuItemAutoFillIdentifier").
    static let blockedMenuIdentifierParts = [
        "paste", "autofill", "opendocument", "openrecent", "services", "share", "print", "runpagelayout",
        "import", "startdictation",
    ]

    static func isBlockedMenuIdentifier(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        return blockedMenuIdentifierParts.contains { lowered.contains($0) }
    }

    /// Refused keystrokes: ⌘V (and variants) pastes and ⌘O opens files.
    /// The Apple menu's shortcuts act on the whole Mac (⇧⌘Q log out, ⌃⌘Q lock,
    /// ⌥⌘⎋ force quit), and Control with a function key moves keyboard focus
    /// to the menu bar, Dock or status menus, from where the Apple menu opens.
    static func isBlockedShortcut(key: String, modifiers: CGEventFlags) -> Bool {
        let key = key.lowercased()
        let command = modifiers.contains(.maskCommand)
        if command && ["v", "o"].contains(key) { return true }
        if command && key == "q" && (modifiers.contains(.maskShift) || modifiers.contains(.maskControl)) { return true }
        if command && modifiers.contains(.maskAlternate) && ["escape", "esc"].contains(key) { return true }
        if modifiers.contains(.maskControl) && key.hasPrefix("f") && key.count > 1 { return true }
        return false
    }
}
