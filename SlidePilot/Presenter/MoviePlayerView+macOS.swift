#if os(macOS)
import AVKit
import SwiftUI

/// The system video player (`AVPlayerView`) for a `\movie` on the slide (NAV-07).
///
/// Wrapped instead of SwiftUI's `VideoPlayer`, which cannot hide its controls or keep the
/// keyboard: the player never becomes first responder, so the arrow and Page keys keep
/// changing slides while a video is shown (NAV-08, old bug SlidePilot-macOS#84).
struct MoviePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let showsControls: Bool
    /// Called with `isReadyForDisplay`: the player is black until its first frame is
    /// ready, so the slide keeps it hidden over the poster until then (#141).
    let readinessChanged: (Bool) -> Void

    /// Like the old app, the presentation has controls too: it may be the only window the
    /// presenter sees.
    static func showsControls(isPresenter: Bool) -> Bool { true }

    func makeCoordinator() -> MoviePlayerReadiness { MoviePlayerReadiness() }

    func makeNSView(context: Context) -> SlideMoviePlayerView {
        let view = SlideMoviePlayerView()
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        // A slide video is part of the talk, not media playback: it must not show in Now
        // Playing, take the media keys or claim the audio route (old bug SlidePilot-macOS#95).
        view.updatesNowPlayingInfoCenter = false
        update(view, readiness: context.coordinator)
        // The slide gives every player its own view, so this reports that player's frame.
        context.coordinator.observe(view, \.isReadyForDisplay)
        return view
    }

    func updateNSView(_ view: SlideMoviePlayerView, context: Context) {
        update(view, readiness: context.coordinator)
    }

    static func dismantleNSView(_ view: SlideMoviePlayerView, coordinator: MoviePlayerReadiness) {
        coordinator.stop()
        view.player = nil
    }

    private func update(_ view: SlideMoviePlayerView, readiness: MoviePlayerReadiness) {
        readiness.changed = readinessChanged
        if view.player !== player { view.player = player }
        view.showsControls = showsControls
    }
}

/// An `AVPlayerView` that leaves the keyboard to the slide navigation (NAV-08). Its
/// controls still work with the mouse.
final class SlideMoviePlayerView: AVPlayerView {
    /// The PDF sets the player's size, which can be too small for the control bar: then
    /// only the system's minimal play button is shown, so no control is cut off.
    /// On macOS 26 the bar drops items as the player shrinks; at about 160 pt wide its
    /// outer buttons are cut off.
    private static let fullControlsSize = CGSize(width: 180, height: 60)

    var showsControls = true {
        didSet { updateControlsStyle() }
    }

    override var acceptsFirstResponder: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateControlsStyle()
    }

    private func updateControlsStyle() {
        let fits = bounds.width >= Self.fullControlsSize.width && bounds.height >= Self.fullControlsSize.height
        let style: AVPlayerViewControlsStyle = showsControls ? (fits ? .default : .minimal) : .none
        if controlsStyle != style { controlsStyle = style }
    }
}
#endif
