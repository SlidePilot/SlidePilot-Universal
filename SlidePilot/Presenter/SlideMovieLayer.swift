import AVFoundation
import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// The videos of a slide, each in the system player at its place on the slide (NAV-07).
///
/// Part of the slide surface (ADR 0010): the PDF decides where a video goes, so it is
/// placed by hand; the player itself is AVKit's. It is separate from the drawing layer
/// above the slide. Without folder access the PDF's poster stays visible and the presenter
/// gets a button to grant it.
struct SlideMovieLayer: View {
    let movies: [SlideMovie]
    let region: PageRegion
    let page: Int
    /// The presenter's current slide asks for access; the presentation only shows videos.
    let isPresenter: Bool

    @Environment(LinkedFiles.self) private var linkedFiles: LinkedFiles?

    var body: some View {
        if let linkedFiles {
            GeometryReader { proxy in
                let size = proxy.size
                ForEach(Self.identified(movies), id: \.id) { item in
                    let movie = item.movie
                    if let rect = movie.unitRect(in: region), let url = linkedFiles.url(for: movie.reference) {
                        SlideMovieView(movie: movie, url: url, page: page, isPresenter: isPresenter, linkedFiles: linkedFiles)
                            .frame(width: rect.width * size.width, height: rect.height * size.height)
                            // The player's own view extends into the safe area on iPad.
                            .clipped()
                            .position(x: rect.midX * size.width, y: rect.midY * size.height)
                    }
                }
            }
            // A video reaching past a split-notes half must not cover the notes.
            .clipped()
        }
    }

    private struct Item {
        let id: String
        let movie: SlideMovie
    }

    /// Identifies a video by its reference and how often it came before on the page, so an
    /// overlay build step that shows the same `\movie` again keeps its view (#140).
    private static func identified(_ movies: [SlideMovie]) -> [Item] {
        var seen: [String: Int] = [:]
        return movies.map { movie in
            let count = seen[movie.reference, default: 0]
            seen[movie.reference] = count + 1
            return Item(id: "\(count) \(movie.reference)", movie: movie)
        }
    }
}

/// One video: the shared player, or what to do when the file cannot be read.
private struct SlideMovieView: View {
    let movie: SlideMovie
    let url: URL
    let page: Int
    let isPresenter: Bool
    let linkedFiles: LinkedFiles

    @State private var player: AVPlayer?
    @State private var isMissing = false
    /// The system player is black until its first frame is ready, so it stays hidden over
    /// the PDF's poster until then (#141).
    @State private var isShown = false
    /// A player that already played elsewhere (the other window, an earlier view) has its
    /// frame at once: it appears without a fade.
    @State private var fadesIn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Load: Equatable {
        let url: URL
        let page: Int
        let access: Int
    }

    var body: some View {
        // A clear base, so the task runs before there is a player to show.
        ZStack {
            Color.clear
            if let player {
                MoviePlayerView(
                    player: player,
                    showsControls: MoviePlayerView.showsControls(isPresenter: isPresenter),
                    readinessChanged: show
                )
                // A new player gets a new view: a reused one could still report the
                // previous player's frame as ready.
                .id(ObjectIdentifier(player))
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
                .accessibilityHidden(!isShown)
                .accessibilityLabel(Text("Video \(url.lastPathComponent)"))
            } else if isMissing, isPresenter {
                missingFile
            }
        }
        .task(id: Load(url: url, page: page, access: linkedFiles.accessGeneration)) {
            if linkedFiles.isAvailable(url) {
                let next = linkedFiles.player(for: movie, url: url, page: page)
                if next !== player {
                    // A kept player (reload, access change) stays shown; a new one waits.
                    isShown = false
                    fadesIn = next.currentItem?.status != .readyToPlay
                    player = next
                }
                isMissing = false
            } else {
                player = nil
                isShown = false
                isMissing = true
            }
        }
    }

    /// Shows the player once it has a frame. It is not hidden again while it stays the
    /// same player, so a loop or seek never flashes the poster.
    private func show(isReady: Bool) {
        guard isReady, !isShown else { return }
        withAnimation(fadesIn && !reduceMotion ? .easeIn(duration: 0.2) : nil) {
            isShown = true
        }
    }

    /// Over the poster: grant the folder, or say that the file is not there.
    /// The PDF decides the size of the area, so with large text only the symbol may fit;
    /// VoiceOver still reads the full title.
    @ViewBuilder
    private var missingFile: some View {
        if linkedFiles.needsFolderAccess {
            let reason = Text("SlidePilot needs access to the folder of this PDF to play “\(url.lastPathComponent)”.")
            ViewThatFits {
                accessButton.labelStyle(.titleAndIcon)
                accessButton.labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .help(reason)
            .accessibilityHint(reason)
        } else {
            ViewThatFits {
                notFoundLabel.labelStyle(.titleAndIcon)
                notFoundLabel.labelStyle(.iconOnly)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            // Drawn on the PDF's white paper, also in dark mode.
            .environment(\.colorScheme, .light)
        }
    }

    private var accessButton: some View {
        Button {
            linkedFiles.requestFolderAccess()
        } label: {
            Label("Allow Access to Play Video…", systemImage: "folder.badge.questionmark")
        }
    }

    private var notFoundLabel: some View {
        Label("Video “\(url.lastPathComponent)” not found", systemImage: "exclamationmark.triangle")
    }
}
