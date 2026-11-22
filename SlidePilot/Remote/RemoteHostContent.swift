import CoreGraphics
import SlidePilotCore
import SlidePilotRemoteProtocol
import SlidePilotRendering

extension PresentationSession {
    /// What a remote controller sees of this document (REM-04).
    var hostedPresentation: HostedPresentation {
        HostedPresentation(
            id: PresentationID(rawValue: id),
            title: title,
            slideIndex: currentPage,
            slideCount: position.pageCount,
            curtain: RemoteCurtain(curtain),
            notesRTF: notes.rtf(forPage: currentPage),
            contentVersion: contentVersion
        )
    }

    /// Applies a command of a verified controller (REM-05). Slide changes do not start the
    /// timer (TIME-05).
    func perform(_ command: HostCommand) {
        switch command {
        case .nextSlide: showNextPage()
        case .previousSlide: showPreviousPage()
        case .setCurtain(let remote): curtain = Curtain(remote)
        case .pointerMoved(let position): remotePointerLocation = CGPoint(x: position.x, y: position.y)
        case .pointerFinished: remotePointerLocation = nil
        }
    }
}

/// Renders the slide images a controller asked for from the render cache (PRE-02) and
/// compresses them, off the main actor.
enum RemoteSlideImages {
    /// The current and next slide show the audience's half; the notes half is sent only
    /// with split notes, otherwise the controller shows the text notes (REM-04, NOTES-02).
    /// `nil` if a slide cannot be rendered, e.g. after the deck got shorter.
    @concurrent
    nonisolated static func render(
        _ request: SlideImageRequest, from cache: RenderCache, audience: PageRegion, notes notesRegion: PageRegion?
    ) async -> SlideImages? {
        let box = SlidePilotRendering.PixelSize(width: request.size.width, height: request.size.height)
        do {
            let current = try await encoded(cache.image(page: request.slideIndex, region: audience, fitting: box))
            var next: EncodedImage?
            if let nextIndex = request.nextSlideIndex {
                next = try await encoded(cache.image(page: nextIndex, region: audience, fitting: box))
            }
            var notes: EncodedImage?
            if let notesRegion {
                notes = try await encoded(cache.image(page: request.slideIndex, region: notesRegion, fitting: box))
            }
            return SlideImages(presentationID: request.presentationID, slideIndex: request.slideIndex, current: current, next: next, notes: notes)
        } catch {
            return nil
        }
    }

    private nonisolated static func encoded(_ slide: RenderedSlide) throws -> EncodedImage {
        EncodedImage(
            format: .jpeg,
            pixelWidth: slide.image.width,
            pixelHeight: slide.image.height,
            data: try SlideImageEncoder.jpeg(slide.image)
        )
    }
}
