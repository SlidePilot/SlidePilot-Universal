#if os(iOS)
import AVKit
import SwiftUI

/// The system video player (`AVPlayerViewController`) for a `\movie` on the slide (NAV-07).
///
/// Wrapped instead of SwiftUI's `VideoPlayer`, which cannot hide its controls: the external
/// display has no input, so it shows the video without them.
struct MoviePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsControls: Bool
    /// Called with `isReadyForDisplay`: the player is black until its first frame is
    /// ready, so the slide keeps it hidden over the poster until then (#141).
    let readinessChanged: (Bool) -> Void

    /// The external display has no input, so only the presenter has controls.
    static func showsControls(isPresenter: Bool) -> Bool { isPresenter }

    func makeCoordinator() -> MoviePlayerReadiness { MoviePlayerReadiness() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        // A slide video is part of the talk, not media playback: it must not show in
        // Control Center or on the Lock Screen (old bug SlidePilot-macOS#95).
        controller.updatesNowPlayingInfoCenter = false
        Self.configureAudioSession()
        update(controller, readiness: context.coordinator)
        // The slide gives every player its own view, so this reports that player's frame.
        context.coordinator.observe(controller, \.isReadyForDisplay)
        return controller
    }

    /// Plays a video's sound even in Silent Mode, but mixed with other audio: a video
    /// without sound does not stop the music of another app, and a mixable session is
    /// never the Now Playing app.
    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback || session.mode != .moviePlayback
            || session.categoryOptions != [.mixWithOthers] else { return }
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        } catch {
            linkedFilesLog.error("Could not set the audio session category: \(error, privacy: .public)")
        }
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        update(controller, readiness: context.coordinator)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: MoviePlayerReadiness) {
        coordinator.stop()
        controller.player = nil
    }

    private func update(_ controller: AVPlayerViewController, readiness: MoviePlayerReadiness) {
        readiness.changed = readinessChanged
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsControls
    }
}
#endif
