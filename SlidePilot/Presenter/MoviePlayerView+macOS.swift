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

    /// Like the old app, the presentation has controls too: it may be the only window the
    /// presenter sees.
    static func showsControls(isPresenter: Bool) -> Bool { true }

    func makeNSView(context: Context) -> SlideMoviePlayerView {
        let view = SlideMoviePlayerView()
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        update(view)
        return view
    }

    func updateNSView(_ view: SlideMoviePlayerView, context: Context) {
        update(view)
    }

    static func dismantleNSView(_ view: SlideMoviePlayerView, coordinator: ()) {
        view.player = nil
    }

    private func update(_ view: SlideMoviePlayerView) {
        if view.player !== player { view.player = player }
        view.showsControls = showsControls
    }
}

/// An `AVPlayerView` that leaves the keyboard to the slide navigation (NAV-08). Its
/// controls still work with the mouse.
final class SlideMoviePlayerView: AVPlayerView {
    /// The PDF sets the player's size, which can be too small for the control bar: then
    /// only the system's minimal play button is shown, so no control is cut off.
    private static let fullControlsSize = CGSize(width: 320, height: 140)

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
