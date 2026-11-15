import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Renders SlidePilot's own windows into PNGs, from inside the app process.
///
/// This deliberately avoids every screen capture API (ScreenCaptureKit,
/// CGWindowList, `screencapture`): the app only draws its own view hierarchy,
/// so it needs no Screen Recording permission and cannot see other apps, the
/// desktop, the Dock or the menu bar.
enum WindowSnapshot {
    enum Appearance: String, CaseIterable, Sendable {
        case light, dark

        var nsAppearance: NSAppearance? {
            switch self {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// PNG text key that marks a snapshot. `scripts/export-mac-snapshots.py`
    /// exports only PNGs that carry it, and uses its value as the file name.
    static let markerKey = "SlidePilotSnapshot"

    /// Hosts `view` in a titled window, renders it and records the PNG as a
    /// test attachment named `mac-<name>-<appearance>`.
    static func record(
        _ view: some View,
        name: String,
        size: CGSize = CGSize(width: 900, height: 600),
        appearance: Appearance,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let window = makeWindow(view, size: size, appearance: appearance)
        defer { window.close() }

        try await record(window, name: "\(name)-\(appearance.rawValue)", sourceLocation: sourceLocation)
    }

    /// Hosts `view` in a titled window that stays open, for snapshots of several states.
    /// Close it when done.
    static func makeWindow(
        _ view: some View,
        size: CGSize = CGSize(width: 900, height: 600),
        appearance: Appearance
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "SlidePilot"
        window.appearance = appearance.nsAppearance
        let hostingView = NSHostingView(rootView: view)
        // Keep the requested size instead of shrinking to the ideal size.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        window.orderFront(nil)
        return window
    }

    /// Renders a window of this app and records it as a test attachment.
    static func record(
        _ window: NSWindow,
        name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let fileName = "mac-\(name)"
        guard fileName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw Failure(description: "Snapshot names may only contain letters, digits and '-'")
        }
        let png = try await pngData(of: window, title: fileName)
        Attachment.record(PNGAttachment(data: png), named: "\(fileName).png", sourceLocation: sourceLocation)
    }

    private static func pngData(of window: NSWindow, title: String) async throws -> Data {
        // Let SwiftUI finish layout and the first render pass.
        try await Task.sleep(for: .milliseconds(500))
        window.displayIfNeeded()

        // The content view's superview is the window's frame view, which also
        // draws the title bar and toolbar.
        guard let frameView = window.contentView?.superview ?? window.contentView else {
            throw Failure(description: "Window has no content view")
        }
        let bounds = frameView.bounds
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw Failure(description: "Could not create a bitmap for the window")
        }
        frameView.cacheDisplay(in: bounds, to: bitmap)
        guard let cgImage = bitmap.cgImage else {
            throw Failure(description: "Could not read the rendered window")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(description: "Could not create a PNG encoder")
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGTitle: "\(markerKey):\(title)"]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(description: "Could not encode the window as PNG")
        }
        return data as Data
    }
}

/// Attaches already-encoded PNG bytes unchanged, so the marker survives.
private nonisolated struct PNGAttachment: Attachable, Sendable {
    let data: Data

    borrowing func withUnsafeBytes<R>(
        for attachment: borrowing Attachment<PNGAttachment>,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        try data.withUnsafeBytes(body)
    }
}
