import AVFoundation
import SlidePilotCore

/// One shared player for a video on the shown slide, set up from the PDF's activation
/// (NAV-07, #139): the part of the file to play, looping and autostart.
///
/// Owned by `LinkedFiles`, which hands the same player to the presenter and the
/// presentation, so a video that autostarts is heard once.
final class MoviePlayback {
    /// A queue player, so `AVPlayerLooper` can loop without a gap.
    let player = AVQueuePlayer()

    private let url: URL
    private let activation: MovieActivation
    private var looper: AVPlayerLooper?
    /// Reads the file's length for start and duration; cancelled with the playback.
    private var setup: Task<Void, Never>?

    init(url: URL, activation: MovieActivation) {
        self.url = url
        self.activation = activation
        let asset = AVURLAsset(url: url)
        if activation.start == nil, activation.duration == nil {
            // The whole file: ready at once, like a player without options.
            prepare(asset: asset, range: (0, nil))
        } else {
            setup = Task { [weak self] in
                // Without a length (web videos), start and duration are used as written.
                let length = try? await asset.load(.duration)
                guard !Task.isCancelled, let self else { return }
                let seconds = length.map(\.seconds).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                var range = activation.playbackRange(fileDuration: seconds)
                // A loop from a start without a duration runs to the end of the file.
                if activation.loops, range.end == nil, range.start > 0 { range.end = seconds }
                self.prepare(asset: asset, range: range)
            }
        }
    }

    isolated deinit {
        setup?.cancel()
    }

    /// Plays a kept video whose autostart begins on a later build step (#140). A video that
    /// already plays goes on.
    func start() {
        guard player.rate == 0 else { return }
        player.play()
    }

    /// Stops playback for good; the slide no longer shows the video.
    func stop() {
        setup?.cancel()
        looper?.disableLooping()
        player.pause()
    }

    // MARK: - Private

    private func prepare(asset: AVURLAsset, range: (start: TimeInterval, end: TimeInterval?)) {
        let startTime = CMTime(seconds: range.start, preferredTimescale: 600)
        let end = range.end.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let item = AVPlayerItem(asset: asset)
        if activation.loops {
            // Without an end the whole file loops; the looper takes no open-ended range. So a
            // web video whose length cannot be read loops from its beginning, not from start.
            let range = end.map { CMTimeRange(start: startTime, end: $0) } ?? .invalid
            looper = AVPlayerLooper(player: player, templateItem: item, timeRange: range)
        } else {
            if let end { item.forwardPlaybackEndTime = end }
            // A queue player drops a finished item by default, which leaves the player
            // black; like a plain player, it keeps the last frame instead.
            player.actionAtItemEnd = .pause
            player.insert(item, after: nil)
            if range.start > 0 {
                item.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
            }
        }
        // Replaying after the end is left to the system controls.
        if activation.autostarts { player.play() }
    }
}
