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
                ForEach(Array(movies.enumerated()), id: \.offset) { _, movie in
                    if let rect = movie.unitRect(in: region), let url = linkedFiles.url(for: movie.reference) {
                        SlideMovieView(url: url, activation: movie.activation, page: page, isPresenter: isPresenter, linkedFiles: linkedFiles)
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
}

/// One video: the shared player, or what to do when the file cannot be read.
private struct SlideMovieView: View {
    let url: URL
    let activation: MovieActivation
    let page: Int
    let isPresenter: Bool
    let linkedFiles: LinkedFiles

    @State private var player: AVPlayer?
    @State private var isMissing = false

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
                MoviePlayerView(player: player, showsControls: MoviePlayerView.showsControls(isPresenter: isPresenter))
                    .accessibilityLabel(Text("Video \(url.lastPathComponent)"))
            } else if isMissing, isPresenter {
                missingFile
            }
        }
        .task(id: Load(url: url, page: page, access: linkedFiles.accessGeneration)) {
            if linkedFiles.isAvailable(url) {
                player = linkedFiles.player(for: url, page: page, activation: activation)
                isMissing = false
            } else {
                player = nil
                isMissing = true
            }
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
