import AppKit
import ApplicationServices

// SlidePilot Test Host: lets Claude capture and drive the SlidePilot test build
// on the Mac without any permission for Claude itself (ADR 0018).
// A menu bar item shows that it runs, its permissions and the last action.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let host = Host()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask once; the grants then belong to this exact binary.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        // The literal value of kAXTrustedCheckOptionPrompt (a C global that
        // Swift 6 treats as shared mutable state).
        let promptKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        host.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        host.start()
    }

    /// Quitting while recording would leave an unplayable movie file.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard host.isRecording else { return .terminateNow }
        Task {
            await host.stopRecordingIfNeeded()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func updateIcon() {
        let symbol = host.isRecording ? "record.circle" : "camera.viewfinder"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SlidePilot Test Host")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        info("SlidePilot Test Host")
        info("Captures and controls only \(Policy.targetBundleID)")
        menu.addItem(.separator())
        info("Screen Recording: " + (CGPreflightScreenCaptureAccess() ? "allowed" : "not allowed"))
        info("Accessibility: " + (AXIsProcessTrusted() ? "allowed" : "not allowed"))
        info(host.isRecording ? "Recording the test build" : "Not recording")
        info("Last: " + host.lastAction.prefix(80))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Privacy & Security Settings…", action: #selector(openPrivacySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Test Host", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action == #selector(openPrivacySettings) { item.target = self }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
