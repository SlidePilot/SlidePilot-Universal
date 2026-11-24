import CoreGraphics
import Foundation
import SlidePilotCore

/// Renders and caches slide images of one PDF (ADR 0005, PRE-01, PRE-02).
///
/// - The presenter's current slide sets the *focus*. The cache then renders the current and
///   next page first, the previous and the two pages after next in the background, and
///   cancels queued jobs for pages that left that neighborhood.
/// - One image per page and region; smaller views (next-slide preview, remote) scale it down.
/// - Memory is limited by a byte budget the cache counts itself. The current and next page
///   are never evicted; other images go least recently used, outside the neighborhood first.
/// - Thumbnails have their own small store and render lazily on request.
public actor RenderCache {
    public struct Configuration: Sendable {
        public var budgetBytes: Int
        public var thumbnailBudgetBytes: Int
        public var backgroundWorkers: Int

        public init(budgetBytes: Int, thumbnailBudgetBytes: Int, backgroundWorkers: Int) {
            self.budgetBytes = budgetBytes
            self.thumbnailBudgetBytes = thumbnailBudgetBytes
            self.backgroundWorkers = backgroundWorkers
        }

        /// Budgets measured in #8 (`docs/prototypes/render-cache.md`).
        /// Thumbnails are about 0.5 MiB each, so 32 MiB holds about 64 of them.
        public static var platformDefault: Configuration {
            #if os(macOS)
            Configuration(budgetBytes: 512 << 20, thumbnailBudgetBytes: 32 << 20, backgroundWorkers: 2)
            #else
            Configuration(budgetBytes: 192 << 20, thumbnailBudgetBytes: 16 << 20, backgroundWorkers: 2)
            #endif
        }
    }

    /// Where the presenter is: the current page, the region the audience sees and its size.
    private struct Focus {
        let page: Int
        let region: PageRegion
        let box: PixelSize
    }

    private struct Job {
        let id: UInt64
        /// The aspect-fitted size the job renders.
        let size: PixelSize
        let task: Task<RenderedSlide, any Error>
    }

    public nonisolated let info: PDFDocumentInfo
    private let configuration: Configuration
    /// Renders the current and next page.
    private let foreground: SlideRasterizer
    /// Render the rest of the neighborhood and thumbnails.
    private let background: [SlideRasterizer]
    private var nextBackgroundWorker = 0

    private var slides = ImageStore()
    private var thumbnails = ImageStore()
    private var jobs: [SlideKey: Job] = [:]
    private var thumbnailJobs: [SlideKey: Job] = [:]
    private var nextJobID: UInt64 = 0
    private var focus: Focus?
    /// Links per page, running or done; tiny, kept for the session.
    private var pageLinks: [Int: Task<[SlideLink], Never>] = [:]
    /// Movies per page, like the links.
    private var pageMovies: [Int: Task<[SlideMovie], Never>] = [:]
    private var linkedFiles: Task<[String], Never>?
    /// Holds the videos stored inside the PDF (#142).
    private let embeddedFiles: EmbeddedFileStore
    /// The temporary files this PDF's pages have returned so far.
    private var usedEmbeddedFiles: Set<URL> = []

    /// - Parameters:
    ///   - data: The PDF. Every worker opens its own `PDFDocument` from it (DEF-02).
    ///   - info: The result of `PDFInspector.inspect(data)`.
    ///   - embeddedFiles: Where videos stored inside the PDF are written. Pass the document's
    ///     store, so the caches of a reloaded PDF share the files.
    public init(
        data: Data,
        info: PDFDocumentInfo,
        configuration: Configuration = .platformDefault,
        embeddedFiles: EmbeddedFileStore = EmbeddedFileStore()
    ) {
        self.info = info
        self.configuration = configuration
        self.embeddedFiles = embeddedFiles
        foreground = SlideRasterizer(data: data)
        background = (0..<max(0, configuration.backgroundWorkers)).map { _ in SlideRasterizer(data: data) }
    }

    // Jobs hold the cache weakly, so closing a document cancels its queued renders here.
    deinit {
        for job in jobs.values { job.task.cancel() }
        for job in thumbnailJobs.values { job.task.cancel() }
    }

    // MARK: - Slides

    /// The image of `region` of `page`, at least as large as needed to fill `box` (aspect fit).
    public func image(page: Int, region: PageRegion, fitting box: PixelSize) async throws -> RenderedSlide {
        let key = SlideKey(page: page, region: region)
        let needed = try neededSize(for: key, fitting: box)
        while true {
            if let cached = slides.use(key), cached.pixelSize.covers(needed) {
                return cached
            }
            let job = jobs[key].flatMap { $0.size.covers(needed) ? $0 : nil }
                ?? startJob(for: key, box: box, size: needed, on: worker(for: page))
            do {
                return try await job.task.value
            } catch is CancellationError where !Task.isCancelled {
                // The job was a neighborhood job the presenter has moved away from,
                // but this caller still wants the page: start a new job.
                if jobs[key]?.id == job.id { jobs[key] = nil }
                continue
            }
        }
    }

    /// Moves the neighborhood to `page`. Call it whenever the presenter's current slide,
    /// its region or its size changes; queued jobs for pages outside the new neighborhood
    /// are cancelled and the neighborhood is rendered in priority order.
    public func focus(on page: Int, region: PageRegion, fitting box: PixelSize) {
        guard info.pageSizes.indices.contains(page) else { return }
        focus = Focus(page: page, region: region, box: box)

        let neighborhood = neighborhoodKeys
        for (key, job) in jobs where !neighborhood.contains(key) {
            job.task.cancel()
            jobs[key] = nil
        }

        // Current, next, previous, then further ahead (ADR 0005).
        for offset in [0, 1, -1, 2, 3] {
            let target = page + offset
            guard info.pageSizes.indices.contains(target) else { continue }
            let key = SlideKey(page: target, region: region)
            guard let needed = try? neededSize(for: key, fitting: box) else { continue }
            if let cached = slides.peek(key), cached.pixelSize.covers(needed) { continue }
            if let job = jobs[key], job.size.covers(needed) { continue }
            startJob(for: key, box: box, size: needed, on: worker(for: target))
        }
    }

    /// Frees everything but the neighborhood, e.g. on a memory warning on iPadOS.
    public func shrinkToNeighborhood() {
        slides.removeAll(except: neighborhoodKeys)
        thumbnails.removeAll(except: [])
    }

    // MARK: - Thumbnails

    /// A small image for the slide navigator, rendered lazily on a background worker.
    public func thumbnail(page: Int, region: PageRegion, fitting box: PixelSize) async throws -> RenderedSlide {
        let key = SlideKey(page: page, region: region)
        let needed = try neededSize(for: key, fitting: box)
        if let cached = thumbnails.use(key), cached.pixelSize.covers(needed) {
            return cached
        }
        let job: Job
        if let running = thumbnailJobs[key], running.size.covers(needed) {
            job = running
        } else {
            let rasterizer = nextBackgroundRasterizer()
            let id = makeJobID()
            let task = Task { try await rasterizer.render(page: page, region: region, fitting: box) }
            job = Job(id: id, size: needed, task: task)
            thumbnailJobs[key] = job
        }
        defer { if thumbnailJobs[key]?.id == job.id { thumbnailJobs[key] = nil } }
        let slide = try await job.task.value
        thumbnails.insert(slide, for: key)
        thumbnails.evict(toFit: configuration.thumbnailBudgetBytes, protected: [], preferred: [])
        return slide
    }

    // MARK: - Links

    /// The links on `page` (NAV-05). Read once per page on a background worker, so a
    /// running render of the current slide does not delay them. The presenter and the
    /// presentation ask at the same time; they share one read.
    public func links(page: Int) async -> [SlideLink] {
        if let read = pageLinks[page] { return await read.value }
        let rasterizer = nextBackgroundRasterizer()
        let read = Task { await rasterizer.links(page: page) }
        pageLinks[page] = read
        return await read.value
    }

    // MARK: - Movies and linked files

    /// The movies on `page` (NAV-07), read once per page like the links. A video stored
    /// inside the PDF is written to a temporary file first (#142).
    public func movies(page: Int) async -> [SlideMovie] {
        if let read = pageMovies[page] {
            let movies = await read.value
            // A temporary copy may be gone (system cleanup, the document closed while its
            // views live on): read the page again, so the file is written again.
            let isComplete = movies.allSatisfy { movie in
                movie.embeddedFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? true
            }
            if isComplete { return movies }
            if pageMovies[page] == read { pageMovies[page] = nil }
            return await self.movies(page: page)
        }
        let rasterizer = nextBackgroundRasterizer()
        let store = embeddedFiles
        let read = Task {
            var movies: [SlideMovie] = []
            for extracted in await rasterizer.movies(page: page) {
                if let movie = await extracted.storing(in: store) { movies.append(movie) }
            }
            return movies
        }
        pageMovies[page] = read
        let movies = await read.value
        for movie in movies {
            if let file = movie.embeddedFile { usedEmbeddedFiles.insert(file) }
        }
        return movies
    }

    /// Removes the temporary files of videos that this PDF no longer stores, after a reload
    /// (DOC-08, #142). Reads every page only when the store holds files this PDF has not
    /// shown yet, so a first open does not write every video ahead of time.
    public func removeUnusedEmbeddedFiles() async {
        guard await !embeddedFiles.files.subtracting(usedEmbeddedFiles).isEmpty else { return }
        let mark = await embeddedFiles.mark()
        var used: Set<URL> = []
        for page in 0..<info.pageCount {
            // The document closed or a newer reload took over.
            guard !Task.isCancelled else { return }
            for movie in await movies(page: page) {
                if let file = movie.embeddedFile { used.insert(file) }
            }
        }
        guard !Task.isCancelled else { return }
        // Files that a newer reload asked for since `mark` stay as well.
        await embeddedFiles.removeAll(except: used, requestedSince: mark)
    }

    /// Every file the PDF refers to with `\movie` or a `run:` link, as written in the PDF,
    /// without duplicates. The app asks for folder access when this is not empty (ADR 0012).
    public func linkedFileReferences() async -> [String] {
        if let linkedFiles { return await linkedFiles.value }
        let rasterizer = nextBackgroundRasterizer()
        let read = Task { await rasterizer.linkedFileReferences() }
        linkedFiles = read
        return await read.value
    }

    // MARK: - Inspection for tests

    var usedBytes: Int { slides.usedBytes }
    var cachedKeys: Set<SlideKey> { slides.keys }
    var thumbnailBytes: Int { thumbnails.usedBytes }

    // MARK: - Private

    private func neededSize(for key: SlideKey, fitting box: PixelSize) throws(RenderError) -> PixelSize {
        guard info.pageSizes.indices.contains(key.page) else { throw .pageNotFound }
        return box.aspectFit(key.region.size(onPageOfSize: info.pageSizes[key.page]))
    }

    /// Pages near the focus, which are evicted last.
    private var neighborhoodKeys: Set<SlideKey> {
        guard let focus else { return [] }
        return Set((focus.page - 1...focus.page + 3).map { SlideKey(page: $0, region: focus.region) })
    }

    /// The current and next page, which are never evicted.
    private var protectedKeys: Set<SlideKey> {
        guard let focus else { return [] }
        return [SlideKey(page: focus.page, region: focus.region), SlideKey(page: focus.page + 1, region: focus.region)]
    }

    /// Current and next go to the foreground worker, everything else to the background.
    private func worker(for page: Int) -> SlideRasterizer {
        guard let focus, page != focus.page, page != focus.page + 1 else { return foreground }
        return nextBackgroundRasterizer()
    }

    private func nextBackgroundRasterizer() -> SlideRasterizer {
        guard !background.isEmpty else { return foreground }
        defer { nextBackgroundWorker = (nextBackgroundWorker + 1) % background.count }
        return background[nextBackgroundWorker]
    }

    private func makeJobID() -> UInt64 {
        nextJobID += 1
        return nextJobID
    }

    @discardableResult
    private func startJob(for key: SlideKey, box: PixelSize, size: PixelSize, on rasterizer: SlideRasterizer) -> Job {
        jobs[key]?.task.cancel()
        let id = makeJobID()
        let task = Task { [weak self] in
            do {
                let slide = try await rasterizer.render(page: key.page, region: key.region, fitting: box)
                await self?.finishJob(id, for: key, with: slide)
                return slide
            } catch {
                // Cancelled or failed jobs are removed too, so the page can be rendered again.
                await self?.finishJob(id, for: key, with: nil)
                throw error
            }
        }
        let job = Job(id: id, size: size, task: task)
        jobs[key] = job
        return job
    }

    private func finishJob(_ id: UInt64, for key: SlideKey, with slide: RenderedSlide?) {
        if jobs[key]?.id == id { jobs[key] = nil }
        guard let slide else { return }
        slides.insert(slide, for: key)
        slides.evict(toFit: configuration.budgetBytes, protected: protectedKeys, preferred: neighborhoodKeys)
    }
}
