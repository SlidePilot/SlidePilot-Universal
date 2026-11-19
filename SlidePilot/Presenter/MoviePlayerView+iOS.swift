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
        update(controller)
        return controller
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
