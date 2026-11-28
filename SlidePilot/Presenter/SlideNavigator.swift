import SlidePilotCore
import SlidePilotRendering
import SwiftUI

extension FocusedValues {
    /// The session of the focused presenter window, for Show Navigator (LAY-06).
    @Entry var slideNavigator: PresentationSession?
}

/// The presenter with the slide navigator as the sidebar of a split view (LAY-06), or as a
/// sheet on compact width or height (iPhone, narrow iPad window). The system provides
/// resizing. **O**, Esc, the menu and the sidebar or navigator button all drive
/// `session.isNavigatorDisplayed`.
///
/// `slidesChrome` (the clock) and `chrome` (the toolbar items) go on the slides column, so
/// the sidebar keeps the full window height on the Mac. On iPad the document browser's launch
/// scene (REM-07) makes the split view's column bars the document's only bar, so the items
/// and the system sidebar button go there too.
struct SlideNavigatorSplitView<Detail: View, SlidesChrome: ViewModifier, Chrome: ViewModifier>: View {
    let session: PresentationSession
    let slidesChrome: SlidesChrome
    let chrome: Chrome
    @ViewBuilder let detail: Detail

    #if os(iOS)
    // Read outside the split view: its columns report their own, narrower size class.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Compact height counts too: a large iPhone in landscape has regular width, but a
    /// sidebar there leaves the slides column compact and too small to read the slides.
    /// It also keeps a phone on the sheet in both orientations, so rotating it neither
    /// swaps the presentation nor changes the stored navigator setting. (The iPhone Duo's
    /// inner display is regular both ways and keeps the sidebar.)
    private var usesSheet: Bool {
        sizeClass == .compact || verticalSizeClass == .compact
    }
    #endif

    var body: some View {
        #if os(macOS)
        splitView(detail: detail.modifier(slidesChrome).modifier(chrome))
        #else
        Group {
            if usesSheet {
                compactView
            } else {
                splitView(detail: detail.modifier(slidesChrome).modifier(chrome))
            }
        }
        // An open sidebar must not turn into a sheet that appears unasked when an iPad
        // window gets narrow. A rotating iPhone stays on the sheet and never gets here.
        .onChange(of: usesSheet) { _, usesSheet in
            if usesSheet {
                session.isNavigatorDisplayed = false
            }
        }
        #endif
    }

    #if os(iOS)
    /// On compact width (iPhone, narrow iPad window) a split view collapses into a stack with
    /// the navigator below the slides. iOS 26 pops a stack with a swipe anywhere on the
    /// content, which took over the swipe to the previous slide (NAV-01). So the slides are
    /// the only level here and the navigator is a sheet over them. Also used on compact
    /// height (see `usesSheet`).
    private var compactView: some View {
        NavigationStack {
            detail
                .modifier(slidesChrome)
                .modifier(chrome)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Show Navigator", systemImage: "rectangle.grid.1x2") {
                            session.isNavigatorDisplayed = true
                        }
                        .help(Text("Show the slide navigator"))
                        // Layout changes are locked in draw mode (DRAW-05).
                        .disabled(session.drawing.isActive)
                    }
                }
        }
        .sheet(isPresented: sheetBinding) {
            // No bar of its own: the document scene puts its back button into every bar,
            // and in the sheet that button only closes the sheet. Swipe down closes it.
            SlideNavigator(session: session, closesOnSelection: true)
                // The thumbnails sit on the sheet, not on an inset card.
                .listStyle(.plain)
                .padding(.top)
                // A sheet is its own presentation: the presenter's keys don't reach it, so
                // Esc and the clicker keys are handled here too (LAY-06, NAV-01).
                .navigatorEscapeKey(session)
                .slideChangeKeys(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .focusedSceneValue(\.slideNavigator, session)
    }

    private var sheetBinding: Binding<Bool> {
        Binding {
            session.isNavigatorDisplayed && !session.drawing.isActive
        } set: {
            // The sheet also goes away when an iPad window gets wide and the sidebar takes
            // over; that must not close (and save closed) the navigator.
            guard usesSheet else { return }
            session.isNavigatorDisplayed = $0
        }
    }
    #endif

    private func splitView(detail: some View) -> some View {
        NavigationSplitView(columnVisibility: visibility) {
            SlideNavigator(session: session, closesOnSelection: false)
                // The old navigator was 180 pt wide; now it can be resized (approved deviation).
                .navigationSplitViewColumnWidth(min: 120, ideal: 180, max: 400)
                #if os(macOS)
                // `PresenterToolbar` has its own sidebar button at the leading end: the
                // system's lands in the overflow menu while the sidebar is closed. Like the
                // iPad, the Mac takes this only from the sidebar column.
                .toolbar(removing: .sidebarToggle)
                #else
                // Layout changes are locked in draw mode (DRAW-05). The iPad takes this only
                // from the sidebar column.
                .toolbar(removing: session.drawing.isActive ? .sidebarToggle : nil)
                #endif
        } detail: {
            detail
        }
        // The slides make room for the navigator instead of being covered, like in the old app.
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.slideNavigator, session)
    }

    private var visibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            session.isNavigatorDisplayed ? .all : .detailOnly
        } set: {
            // Layout changes are locked in draw mode (DRAW-05).
            guard !session.drawing.isActive else { return }
            session.isNavigatorDisplayed = $0 != .detailOnly
        }
    }
}

extension View {
    /// Esc closes the navigator (LAY-06). Apply it outside the view that takes the keyboard
    /// in the presenter, so Esc arrives wherever the focus is.
    func navigatorEscapeKey(_ session: PresentationSession) -> some View {
        onKeyPress(.escape) {
            guard session.isNavigatorDisplayed, !session.notes.isEditing else { return .ignored }
            session.isNavigatorDisplayed = false
            return .handled
        }
    }
}

/// Show Navigator in the Moderator menu with the old app's plain **O** (LAY-06).
struct NavigatorMenuItems: View {
    @FocusedValue(\.slideNavigator) private var session

    var body: some View {
        Toggle("Show Navigator", isOn: isOn)
            .plainKeyShortcut("o")
            // Layout changes are locked in draw mode (DRAW-05).
            .disabled(session == nil || session?.drawing.isActive == true)
    }

    private var isOn: Binding<Bool> {
        Binding {
            session?.isNavigatorDisplayed ?? false
        } set: {
            session?.isNavigatorDisplayed = $0
        }
    }
}

/// Thumbnails of all slides with a page-number field (LAY-06). The current slide has a
/// frame; choosing a thumbnail shows that slide. A number typed in the field
/// highlights a thumbnail and Return jumps to it.
struct SlideNavigator: View {
    let session: PresentationSession
    /// In the compact sheet the navigator covers the slides, so choosing one closes it.
    let closesOnSelection: Bool

    @State private var pageNumber = ""
    @FocusState private var isPageFieldFocused: Bool
    @FocusState private var isListFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pageCount: Int { session.cache.info.pageCount }

    var body: some View {
        let highlighted = NavigatorPageField.page(for: pageNumber, pageCount: pageCount)
        ScrollViewReader { proxy in
            // No list selection: its highlight has a fixed corner radius that looks odd around
            // small thumbnails. The current slide gets a frame around its thumbnail instead,
            // and the arrow keys reach the presenter, which changes the slide.
            List {
                ForEach(0..<pageCount, id: \.self) { page in
                    Button {
                        choose(page)
                    } label: {
                        ThumbnailRow(
                            cache: session.cache,
                            drawings: session.drawing.drawings,
                            region: session.audienceRegion,
                            page: page,
                            pageCount: pageCount,
                            isCurrent: page == session.currentPage,
                            isHighlighted: page == highlighted && page != session.currentPage
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
            .focused($isListFocused)
            // Typing a letter or digit in the list moves it to the page field, like the old app.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.subtracting(.shift).isEmpty,
                      let character = press.characters.first,
                      press.characters.count == 1,
                      NavigatorPageField.startsInput(character)
                else { return .ignored }
                pageNumber = press.characters
                isPageFieldFocused = true
                return .handled
            }
            .onChange(of: session.currentPage, initial: true) { _, page in
                proxy.scrollTo(page)
                // The old app replaced a half-typed number on every page change.
                pageNumber = ""
            }
            .onChange(of: highlighted) { _, page in
                guard let page else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(page) }
            }
        }
        .modifier(PageNumberField(text: $pageNumber, isFocused: $isPageFieldFocused) {
            guard let highlighted else { return }
            choose(highlighted)
            // The old app selected the number so the next one replaces it.
            pageNumber = ""
        } onEscape: {
            session.isNavigatorDisplayed = false
        })
        #if os(macOS)
        // The page field takes the keyboard whenever the navigator opens, like in the old
        // app, so a page number can be typed right after O. Not on iPad, where it would
        // bring up the on-screen keyboard.
        .task(id: session.isNavigatorDisplayed) {
            guard session.isNavigatorDisplayed else { return }
            // Focus can only move once the field is in the window.
            await Task.yield()
            isPageFieldFocused = true
        }
        #endif
        // Set only while focused, so it does not hide the notes editor's value.
        .focusedSceneValue(\.isEditingText, isPageFieldFocused ? true : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Slide Navigator"))
    }

    private func choose(_ page: Int) {
        session.showPage(page)
        if closesOnSelection {
            session.isNavigatorDisplayed = false
        }
    }
}

/// The page-number field above the thumbnails. A plain text field on both platforms: the
/// Mac sidebar's search field selects its text on Return instead of submitting it, and the
/// iPad column bar that would hold a search field is hidden.
private struct PageNumberField: ViewModifier {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        // Above the list, not over it: the thumbnails never scroll under the field.
        VStack(spacing: 0) {
            // A capsule of Liquid Glass like the system's search fields in bars; a search
            // field itself is not used (see above).
            TextField(text: $text, prompt: Text("Page Number")) {
                Text("Page Number")
            }
            .textFieldStyle(.plain)
            // The plain style shows the label nowhere, and the Mac does not pass it on to
            // VoiceOver, which then reads only the prompt.
            .accessibilityLabel(Text("Page Number"))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            #if os(iOS)
            // Digits with a Return key.
            .keyboardType(.numbersAndPunctuation)
            .submitLabel(.go)
            #endif
            .focused(isFocused)
            .onSubmit(onSubmit)
            // Esc closes the navigator also while typing, like in the old app.
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
            .padding()
            content
        }
    }
}

/// One thumbnail with its page number on the leading side, like in the old app.
private struct ThumbnailRow: View {
    let cache: RenderCache
    let drawings: DocumentDrawings
    /// The audience's half with split notes (NOTES-02).
    let region: PageRegion
    let page: Int
    let pageCount: Int
    /// The slide on screen: a frame in the accent color around the thumbnail.
    let isCurrent: Bool
    /// The page typed in the page field, before Return jumps to it: a lighter frame.
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            // As wide as the largest page number, so all thumbnails line up.
            Text(pageCount, format: .number)
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(page + 1, format: .number)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            SlideThumbnail(cache: cache, page: page, region: region)
                .drawingOverlay(drawings, page: page, region: region)
                // The frame sits just outside the thumbnail, so it grows with it.
                .padding(3)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(.tint, lineWidth: 3)
                    } else if isHighlighted {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(.tint.secondary, lineWidth: 3)
                    }
                }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Slide \(page + 1)"))
        // The slide on screen, or the page typed in the page field that Return shows.
        .accessibilityAddTraits(isCurrent || isHighlighted ? .isSelected : [])
    }
}

/// A slide image from the render cache's thumbnail store (PRE-02). Links are not active.
private struct SlideThumbnail: View {
    let cache: RenderCache
    let page: Int
    let region: PageRegion

    @Environment(\.displayScale) private var displayScale
    @State private var slide: RenderedSlide?
    @State private var box: PixelSize?

    private struct Request: Equatable {
        let cache: ObjectIdentifier
        let page: Int
        let region: PageRegion
        let box: PixelSize?
    }

    var body: some View {
        let scale = displayScale
        // White until the first render arrives: PDF pages are drawn on white paper.
        Color.white
            .aspectRatio(pageSize, contentMode: .fit)
            .overlay {
                if let slide, slide.pageIndex == page, slide.region == region {
                    Image(decorative: slide.image, scale: scale)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .onGeometryChange(for: PixelSize.self) { proxy in
                PixelSize(
                    width: Int((proxy.size.width * scale).rounded(.up)),
                    height: Int((proxy.size.height * scale).rounded(.up))
                )
            } action: { newBox in
                box = newBox
            }
            .task(id: Request(cache: ObjectIdentifier(cache), page: page, region: region, box: box)) {
                await load()
            }
            .slideOutline()
    }

    private var pageSize: CGSize {
        let sizes = cache.info.pageSizes
        let size = sizes.indices.contains(page) ? sizes[page] : .zero
        let fitted = region.size(onPageOfSize: size)
        return fitted.width > 0 && fitted.height > 0 ? fitted : CGSize(width: 4, height: 3)
    }

    private func load() async {
        guard let box, box.width > 0, box.height > 0 else { return }
        // Resizing the sidebar changes the size many times a second; wait until it settles.
        if slide?.pageIndex == page, slide?.region == region {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        guard let rendered = try? await cache.thumbnail(page: page, region: region, fitting: box),
              !Task.isCancelled
        else { return }
        slide = rendered
    }
}
