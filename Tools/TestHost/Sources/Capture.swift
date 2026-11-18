import AppKit
@preconcurrency import ScreenCaptureKit
import Synchronization
import UniformTypeIdentifiers

// Screenshots and recordings. Every filter names the test build's process, so
// ScreenCaptureKit leaves out all other apps, the desktop, notifications and
// windows of system services (the open panel, AutoFill), even where they
// overlap the test build. The cursor is never captured.
// (@preconcurrency: ScreenCaptureKit types are not marked Sendable; the host
// only uses them on the main actor.)

struct WindowInfo {
    let id: CGWindowID
    let title: String
    let frame: CGRect
    let layer: Int
}

@MainActor
final class Capture {
    private var recording: (stream: SCStream, delegate: RecordingDelegate, url: URL, timeout: Task<Void, Never>)?
    /// A stop in progress, so a second stop waits for the same file and a new
    /// recording cannot start until the movie is finalized.
    private var stopping: Task<URL, any Error>?
    var isRecording: Bool { recording != nil || stopping != nil }

    /// On-screen windows of the target, front to back.
    /// Windows on another Space, minimized or just appearing are not on screen;
    /// a short retry covers windows that are still appearing.
    func windows(of target: VerifiedTarget) async throws -> (SCShareableContent, [SCWindow]) {
        for attempt in 0..<4 {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter {
                $0.owningApplication?.processID == target.pid && $0.isOnScreen && $0.frame.width > 1 && $0.frame.height > 1
            }
            if !windows.isEmpty || attempt == 3 { return (content, windows) }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PolicyError.refused("unreachable")
    }

    func windowInfos(of target: VerifiedTarget) async throws -> [WindowInfo] {
        try await windows(of: target).1.map {
            WindowInfo(id: $0.windowID, title: $0.title ?? "", frame: $0.frame, layer: $0.windowLayer)
        }
    }

    /// `windowID == nil`: everything the app shows on the display of its front
    /// window (windows, sheets, menus), cropped to those windows.
    /// Otherwise: that one window on its own.
    func screenshot(of target: VerifiedTarget, windowID: CGWindowID?, to url: URL) async throws -> CGSize {
        let (content, windows) = try await windows(of: target)
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = false
        if let windowID {
            guard let window = windows.first(where: { $0.windowID == windowID }) else {
                throw PolicyError.refused("window \(windowID) does not belong to the test build")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
            config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
        } else {
            let (appFilter, rect) = try appFilter(content: content, windows: windows, target: target)
            filter = appFilter
            config.sourceRect = rect
            config.width = Int(rect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(rect.height * CGFloat(filter.pointPixelScale))
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try writePNG(image, to: url)
        return CGSize(width: image.width, height: image.height)
    }

    func startRecording(of target: VerifiedTarget, to url: URL, maxSeconds: Int, onTimeout: @escaping @MainActor () -> Void) async throws {
        // Check, suspend, set: safe because Host handles one request at a time
        // and the timeout path only stops recordings.
        guard recording == nil, stopping == nil else { throw PolicyError.refused("a recording is already running") }
        let (content, windows) = try await windows(of: target)
        let (filter, rect) = try appFilter(content: content, windows: windows, target: target)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.capturesAudio = false
        config.sourceRect = rect
        config.width = Int(rect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(rect.height * CGFloat(filter.pointPixelScale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mov
        outputConfig.videoCodecType = .h264
        let delegate = RecordingDelegate()
        let output = SCRecordingOutput(configuration: outputConfig, delegate: delegate)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        // A forgotten recording stops on its own.
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(maxSeconds))
            if !Task.isCancelled { onTimeout() }
        }
        recording = (stream, delegate, url, timeout)
    }

    @discardableResult
    func stopRecording() async throws -> URL {
        if let stopping { return try await stopping.value }
        guard let recording else { throw PolicyError.refused("no recording is running") }
        self.recording = nil
        recording.timeout.cancel()
        let stream = recording.stream
        let delegate = recording.delegate
        let url = recording.url
        let task = Task { @MainActor () throws -> URL in
            try await Self.finish(stream: stream, delegate: delegate)
            return url
        }
        stopping = task
        defer { stopping = nil }
        return try await task.value
    }

    private static func finish(stream: SCStream, delegate: RecordingDelegate) async throws {
        // stopCapture fails if the stream already ended (e.g. the test build
        // quit); the delegate still reports how writing the file ended.
        do { try await stream.stopCapture() } catch {}
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { delegate.fail(PolicyError.refused("the recording did not finish")) }
        }
        defer { watchdog.cancel() }
        try await delegate.finished()
    }

    /// A display filter that includes only the target's process.
    private func appFilter(content: SCShareableContent, windows: [SCWindow], target: VerifiedTarget) throws -> (SCContentFilter, CGRect) {
        guard let front = windows.first(where: { $0.windowLayer == 0 }) ?? windows.first else {
            throw PolicyError.refused("the test build has no window on the current screen (another Space, minimized or full screen elsewhere?)")
        }
        let center = CGPoint(x: front.frame.midX, y: front.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }),
              let app = content.applications.first(where: { $0.processID == target.pid }) else {
            throw PolicyError.refused("cannot find the test build's display")
        }
        let union = windows
            .map(\.frame)
            .filter { $0.intersects(display.frame) }
            .reduce(CGRect.null) { $0.union($1) }
            .intersection(display.frame)
        let rect = union.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).integral
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        return (filter, rect)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PolicyError.refused("cannot write \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PolicyError.refused("cannot write \(url.lastPathComponent)")
        }
    }
}

/// Waits for SCRecordingOutput to finish writing the movie file.
/// ScreenCaptureKit calls the delegate on its own queue; the state is behind a Mutex.
final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, Sendable {
    private enum State {
        case running
        case waiting(CheckedContinuation<Void, any Error>)
        case done((any Error)?)
    }
    private let state = Mutex<State>(.running)

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finish(nil) }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { finish(error) }
    /// Ends the wait if ScreenCaptureKit never calls back.
    func fail(_ error: any Error) { finish(error) }

    private func finish(_ error: (any Error)?) {
        let continuation: CheckedContinuation<Void, any Error>? = state.withLock { state in
            if case .waiting(let continuation) = state {
                state = .done(error)
                return continuation
            }
            state = .done(error)
            return nil
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func finished() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let result: (any Error)?? = state.withLock { state in
                if case .done(let error) = state { return .some(error) }
                state = .waiting(continuation)
                return .none
            }
            switch result {
            case .none: break
            case .some(.none): continuation.resume()
            case .some(.some(let error)): continuation.resume(throwing: error)
            }
        }
    }
}
