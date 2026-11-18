import AppKit
import ApplicationServices

// Request loop. Claude's sandboxed shell (scripts/mac-test-host.py) writes JSON
// requests into the exchange folder; the host answers each with a JSON response
// and writes captures into out/. The host has no network access and no other
// way to receive commands.

@MainActor
final class Host {
    static let exchange = URL(fileURLWithPath: "/private/tmp/claude/slidepilot-testhost", isDirectory: true)
    private var requests: URL { Self.exchange.appendingPathComponent("requests", isDirectory: true) }
    private var responses: URL { Self.exchange.appendingPathComponent("responses", isDirectory: true) }
    var inbox: URL { Self.exchange.appendingPathComponent("inbox", isDirectory: true) }
    private var out: URL { Self.exchange.appendingPathComponent("out", isDirectory: true) }

    private let capture = Capture()
    private let input = Input()
    private var timer: Timer?
    private var busy = false
    private(set) var lastAction = "Waiting for commands"
    var onChange: (() -> Void)?
    var isRecording: Bool { capture.isRecording }

    /// Finalizes a running recording, e.g. before the host quits.
    func stopRecordingIfNeeded() async {
        if capture.isRecording { _ = try? await capture.stopRecording() }
    }

    func start() {
        prepareExchange()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // Common modes: requests keep running while the status menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The exchange folders must be real folders owned by this user; a symbolic
    /// link could redirect captures or documents elsewhere.
    private func prepareExchange() {
        let manager = FileManager.default
        for url in [Self.exchange, requests, responses, inbox, out] {
            try? manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func exchangeIsSafe() -> Bool {
        for url in [Self.exchange, requests, responses, inbox, out] {
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else {
                return false
            }
        }
        return true
    }

    private func poll() {
        guard !busy else { return }
        prepareExchange()
        guard exchangeIsSafe() else {
            setLastAction("Exchange folder is not safe; ignoring requests")
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: requests, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else { return }
        busy = true
        Task {
            await handle(file)
            busy = false
        }
    }

    private func handle(_ file: URL) async {
        let data = try? Data(contentsOf: file)
        try? FileManager.default.removeItem(at: file)
        guard let data, data.count < 1_000_000,
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = request["id"] as? String,
              (try? Policy.checkedFileName(id + ".json", extensions: ["json"])) != nil,
              let command = request["command"] as? String else {
            return
        }
        let args = request["args"] as? [String: Any] ?? [:]
        var response: [String: Any] = ["id": id]
        do {
            response["result"] = try await run(command, args)
            response["ok"] = true
            setLastAction("\(command): ok")
        } catch {
            response["ok"] = false
            response["error"] = "\(error)"
            setLastAction("\(command): \(error)")
        }
        if let json = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: responses.appendingPathComponent(id + ".json"), options: .atomic)
        }
    }

    private func setLastAction(_ text: String) {
        lastAction = text
        onChange?()
    }

    // MARK: Commands

    private func run(_ command: String, _ args: [String: Any]) async throws -> Any {
        switch command {
        case "status":
            let running = try? Policy.currentTarget()
            return [
                "screenRecording": CGPreflightScreenCaptureAccess(),
                "accessibility": AXIsProcessTrusted(),
                "target": Policy.targetBundleID,
                "targetRunning": running != nil,
                "recording": capture.isRecording,
            ] as [String: Any]

        case "launch":
            guard let path = args["app"] as? String, path.hasPrefix("/") else {
                throw PolicyError.refused("launch needs the absolute path of the test build (app)")
            }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            try Policy.verifyBundle(at: url)
            let documents = try (args["documents"] as? [String] ?? []).map { try Policy.inboxDocument($0, inbox: inbox) }
            if capture.isRecording { _ = try? await capture.stopRecording() }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Policy.targetBundleID) {
                app.forceTerminate()
            }
            try await Task.sleep(for: .milliseconds(500))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // English, so menu titles match the blocked list; no restored windows.
            var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ApplePersistenceIgnoreState", "YES"]
            if let appearance = args["appearance"] as? String {
                guard ["light", "dark"].contains(appearance) else { throw PolicyError.refused("appearance is light or dark") }
                // Read by the test build itself (TestHostAppearance.swift).
                arguments += ["-SlidePilotTestAppearance", appearance]
            }
            configuration.arguments = arguments
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            guard app.bundleURL?.resolvingSymlinksInPath() == url else {
                throw PolicyError.refused("a different app was launched")
            }
            _ = try Policy.currentTarget()
            if !documents.isEmpty {
                try await openDocuments(documents, appURL: url)
            }
            return ["pid": Int(app.processIdentifier)]

        case "open":
            let target = try Policy.currentTarget()
            guard let appURL = target.app.bundleURL else { throw PolicyError.refused("unknown app location") }
            let documents = try (args["documents"] as? [String] ?? []).map { try Policy.inboxDocument($0, inbox: inbox) }
            guard !documents.isEmpty else { throw PolicyError.refused("open needs documents") }
            try await openDocuments(documents, appURL: appURL)
            return "opened \(documents.count) document(s)"

        case "activate":
            let target = try Policy.currentTarget()
            input.bringToFront(target: target, window: nil)
            return "activated"

        case "quit":
            let target = try Policy.currentTarget()
            if capture.isRecording { try await capture.stopRecording() }
            target.app.terminate()
            return "quit"

        case "windows":
            let target = try Policy.currentTarget()
            return try await capture.windowInfos(of: target).map {
                ["id": Int($0.id), "title": $0.title, "layer": $0.layer,
                 "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]] as [String: Any]
            }

        case "screenshot":
            let target = try Policy.currentTarget()
            let name = try Policy.checkedFileName(args["name"] as? String ?? "", extensions: ["png"])
            let windowID = (args["window"] as? Int).map { CGWindowID($0) }
            try refuseIfAppleMenuOpen(target)
            let size = try await capture.screenshot(of: target, windowID: windowID, to: out.appendingPathComponent(name))
            return ["file": name, "width": Int(size.width), "height": Int(size.height)]

        case "record-start":
            let target = try Policy.currentTarget()
            let name = try Policy.checkedFileName(args["name"] as? String ?? "", extensions: ["mov"])
            let seconds = min(max(args["maxSeconds"] as? Int ?? 60, 1), 300)
            try refuseIfAppleMenuOpen(target)
            try await capture.startRecording(of: target, to: out.appendingPathComponent(name), maxSeconds: seconds) { [weak self] in
                Task {
                    guard let self else { return }
                    do {
                        try await self.capture.stopRecording()
                        self.setLastAction("Recording stopped after \(seconds) s")
                    } catch {
                        self.setLastAction("Recording failed: \(error)")
                    }
                }
            }
            onChange?()
            return ["file": name, "maxSeconds": seconds]

        case "record-stop":
            let url = try await capture.stopRecording()
            onChange?()
            return ["file": url.lastPathComponent]

        case "tree":
            return input.tree(of: try Policy.currentTarget())

        case "press":
            let target = try Policy.currentTarget()
            let match = (args["match"] as? [String: String]).map {
                Input.Match(role: $0["role"], title: $0["title"], identifier: $0["id"], description: $0["label"])
            }
            return try input.press(target: target, path: args["path"] as? String, match: match)

        case "menu":
            let target = try Policy.currentTarget()
            guard let titles = args["path"] as? [String] else { throw PolicyError.refused("menu needs path") }
            return try input.menu(target: target, titles: titles, open: args["open"] as? Bool ?? false)

        case "key":
            let target = try Policy.currentTarget()
            guard let combo = args["keys"] as? String else { throw PolicyError.refused("key needs keys") }
            try input.key(target: target, combo: combo, menuOpen: input.isMenuOpen(target: target))
            return "pressed \(combo)"

        case "type":
            let target = try Policy.currentTarget()
            guard let text = args["text"] as? String else { throw PolicyError.refused("type needs text") }
            try await input.type(target: target, text: text, menuOpen: input.isMenuOpen(target: target))
            return "typed \(text.count) characters"

        case "click", "scroll", "drag":
            let target = try Policy.currentTarget()
            let window = try await window(args, target: target)
            let menuOpen = input.isMenuOpen(target: target)
            if !menuOpen {
                input.bringToFront(target: target, window: window)
                try await Task.sleep(for: .milliseconds(300))
            }
            switch command {
            case "click":
                let button = Input.Button(rawValue: args["button"] as? String ?? "left") ?? .left
                try await input.click(target: target, window: window, at: try point(args["at"]), button: button, count: args["count"] as? Int ?? 1, menuOpen: menuOpen)
            case "scroll":
                try input.scroll(target: target, window: window, at: try point(args["at"]),
                                 dx: Int32(args["dx"] as? Int ?? 0), dy: Int32(args["dy"] as? Int ?? 0), menuOpen: menuOpen)
            default:
                let points = try (args["points"] as? [Any] ?? []).map(point)
                try await input.drag(target: target, window: window, points: points, menuOpen: menuOpen)
            }
            return "\(command) in window \(window.id)"

        default:
            throw PolicyError.refused("unknown command \(command)")
        }
    }

    /// The Apple menu shows recent apps and documents of the user.
    private func refuseIfAppleMenuOpen(_ target: VerifiedTarget) throws {
        if input.isAppleMenuOpen(target: target) {
            throw PolicyError.refused("the Apple menu is open; close it with escape first")
        }
    }

    private func openDocuments(_ documents: [URL], appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(documents, withApplicationAt: appURL, configuration: configuration)
    }

    private func window(_ args: [String: Any], target: VerifiedTarget) async throws -> WindowInfo {
        let windows = try await capture.windowInfos(of: target)
        if let id = args["window"] as? Int {
            guard let window = windows.first(where: { Int($0.id) == id }) else {
                throw PolicyError.refused("window \(id) does not belong to the test build")
            }
            return window
        }
        guard let front = windows.first(where: { $0.layer == 0 }) else {
            throw PolicyError.refused("the test build has no window on screen")
        }
        return front
    }

    private func point(_ value: Any?) throws -> CGPoint {
        guard let pair = value as? [Any], pair.count == 2,
              let x = (pair[0] as? NSNumber)?.doubleValue, let y = (pair[1] as? NSNumber)?.doubleValue else {
            throw PolicyError.refused("a point is [x, y]")
        }
        return CGPoint(x: x, y: y)
    }
}
