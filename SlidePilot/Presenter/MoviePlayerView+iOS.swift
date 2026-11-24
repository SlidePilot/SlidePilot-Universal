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

    /// The external display has no input, so only the presenter has controls.
    static func showsControls(isPresenter: Bool) -> Bool { isPresenter }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        // A slide video is part of the talk, not media playback: it must not show in
        // Control Center or on the Lock Screen (old bug SlidePilot-macOS#95).
        controller.updatesNowPlayingInfoCenter = false
        Self.configureAudioSession()
        update(controller)
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
        update(controller)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }

    private func update(_ controller: AVPlayerViewController) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsControls
    }
}
#endif
