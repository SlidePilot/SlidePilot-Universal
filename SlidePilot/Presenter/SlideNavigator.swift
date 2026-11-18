import SlidePilotCore
import SlidePilotRendering
import SwiftUI

extension FocusedValues {
    /// The session of the focused presenter window, for Show Navigator (LAY-06).
    @Entry var slideNavigator: PresentationSession?
}

/// The presenter with the slide navigator as the sidebar of a split view (LAY-06). The
/// system provides resizing and, in a narrow iPad window, one column at a time. **O**, Esc,
/// the menu and the sidebar button all drive `session.isNavigatorDisplayed`.
///
/// `slidesChrome` (the clock) always goes on the slides column. `chrome` adds the toolbar
/// items: on the Mac to the slides column, so the sidebar keeps the full window height. On
/// iPad a document window always shows the document's own bar above a split view's column
/// bars; the column bars are hidden and `chrome` goes on the document's bar, so there is
/// one bar, as without the navigator.
struct SlideNavigatorSplitView<Detail: View, SlidesChrome: ViewModifier, Chrome: ViewModifier>: View {
    let session: PresentationSession
    let slidesChrome: SlidesChrome
    let chrome: Chrome
    @ViewBuilder let detail: Detail

    #if os(iOS)
    // Read outside the split view: its columns report their own, narrower size class.
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(macOS)
        splitView(detail: detail.modifier(slidesChrome).modifier(chrome))
            // Esc reaches the window as "cancel", also from the page field.
            // Only while the navigator is shown, so other views still get Esc.
            .onExitCommand(perform: exitCommand)
        #else
        splitView(detail: detail.modifier(slidesChrome).toolbar(.hidden, for: .navigationBar))
            .modifier(chrome)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigatorToggle(session: session)
                }
            }
            .onKeyPress(.escape) {
                guard session.isNavigatorDisplayed else { return .ignored }
                closeNavigator()
                return .handled
            }
        #endif
    }

    private func splitView(detail: some View) -> some View {
        NavigationSplitView(columnVisibility: visibility, preferredCompactColumn: compactColumn) {
            SlideNavigator(session: session, closesOnSelection: isCompact)
                // The old navigator was 180 pt wide; now it can be resized (approved deviation).
                .navigationSplitViewColumnWidth(min: 120, ideal: 180, max: 400)
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        } detail: {
            detail
        }
        // The slides make room for the navigator instead of being covered, like in the old app.
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.slideNavigator, session)
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    #if os(macOS)
    private var exitCommand: (() -> Void)? {
        guard session.isNavigatorDisplayed else { return nil }
        return { session.isNavigatorDisplayed = false }
    }
    #endif

    private func closeNavigator() {
        session.isNavigatorDisplayed = false
    }

    private var visibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            session.isNavigatorDisplayed ? .all : .detailOnly
        } set: {
            session.isNavigatorDisplayed = $0 != .detailOnly
        }
    }

    private var compactColumn: Binding<NavigationSplitViewColumn> {
        Binding {
            session.isNavigatorDisplayed ? .sidebar : .detail
        } set: {
            session.isNavigatorDisplayed = $0 == .sidebar
        }
    }
}

#if os(iOS)
/// The sidebar button of the document's bar on iPad, where the split view's own button is
/// hidden with its column bar.
private struct NavigatorToggle: View {
    let session: PresentationSession

    var body: some View {
        Button {
            session.isNavigatorDisplayed.toggle()
        } label: {
            if session.isNavigatorDisplayed {
                Label("Hide Navigator", systemImage: "sidebar.leading")
            } else {
                Label("Show Navigator", systemImage: "sidebar.leading")
            }
        }
    }
}
#endif

/// Show Navigator in the Moderator menu with the old app's plain **O** (LAY-06).
struct NavigatorMenuItems: View {
    @FocusedValue(\.slideNavigator) private var session

    var body: some View {
        Toggle("Show Navigator", isOn: isOn)
            .plainKeyShortcut("o")
            .disabled(session == nil)
    }

    private var isOn: Binding<Bool> {
        Binding {
            session?.isNavigatorDisplayed ?? false
        } set: {
            session?.isNavigatorDisplayed = $0
        }
    }
}

/// Thumbnails of all slides with a page-number field (LAY-06). The current slide is the
/// list's selection; choosing a thumbnail shows that slide. A number typed in the field
/// highlights a thumbnail and Return jumps to it.
struct SlideNavigator: View {
    let session: PresentationSession
    /// In a narrow iPad window the navigator covers the slides, so choosing one closes it.
    let closesOnSelection: Bool

    @State private var pageNumber = ""
    @FocusState private var isPageFieldFocused: Bool
    @FocusState private var isListFocused: Bool

    private var pageCount: Int { session.cache.info.pageCount }

    var body: some View {
        let highlighted = NavigatorPageField.page(for: pageNumber, pageCount: pageCount)
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(0..<pageCount, id: \.self) { page in
                    ThumbnailRow(
                        cache: session.cache,
                        page: page,
                        pageCount: pageCount,
                        isHighlighted: page == highlighted && page != session.currentPage
                    )
                    .tag(page)
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
                withAnimation { proxy.scrollTo(page) }
            }
        }
        .modifier(PageNumberField(text: $pageNumber, isFocused: $isPageFieldFocused) {
            guard let highlighted else { return }
            choose(highlighted)
            // The old app selected the number so the next one replaces it.
            pageNumber = ""
        })
        #if os(macOS)
        // The list takes the keyboard on open; on iPad no field is focused, so the
        // on-screen keyboard stays down.
        .onAppear { isListFocused = true }
        #endif
        .focusedSceneValue(\.isEditingText, isPageFieldFocused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Slide Navigator"))
    }

    private var selection: Binding<Int?> {
        Binding {
            session.currentPage
        } set: { page in
            guard let page else { return }
            choose(page)
        }
    }

    private func choose(_ page: Int) {
        session.showPage(page)
        if closesOnSelection {
            session.isNavigatorDisplayed = false
        }
    }
}

/// The page-number field: the sidebar's search field on the Mac, a text field above the
/// thumbnails on iPad (the column bar that would hold a search field is hidden there).
private struct PageNumberField: ViewModifier {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .searchable(text: $text, placement: .sidebar, prompt: Text("Page Number"))
            .searchFocused(isFocused)
            .onSubmit(of: .search, onSubmit)
        #else
        content
            // A bar: the system blurs the thumbnails that scroll under it.
            .safeAreaBar(edge: .top) {
                TextField(text: $text, prompt: Text("Page Number")) {
                    Text("Page Number")
                }
                .textFieldStyle(.roundedBorder)
                // Digits with a Return key.
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.go)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .padding()
            }
        #endif
    }
}

/// One thumbnail with its page number on the leading side, like in the old app.
private struct ThumbnailRow: View {
    let cache: RenderCache
    let page: Int
    let pageCount: Int
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
            SlideThumbnail(cache: cache, page: page)
                .overlay {
                    // The page typed in the page field, before Return jumps to it.
                    if isHighlighted {
                        Rectangle().strokeBorder(.tint, lineWidth: 3)
                    }
                }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Slide \(page + 1)"))
        // The page typed in the page field; Return shows it.
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// A slide image from the render cache's thumbnail store (PRE-02). Links are not active.
private struct SlideThumbnail: View {
    let cache: RenderCache
    let page: Int

    @Environment(\.displayScale) private var displayScale
    @State private var slide: RenderedSlide?
    @State private var box: PixelSize?

    private struct Request: Equatable {
        let cache: ObjectIdentifier
        let page: Int
        let box: PixelSize?
    }

    var body: some View {
        let scale = displayScale
        // White until the first render arrives: PDF pages are drawn on white paper.
        Color.white
            .aspectRatio(pageSize, contentMode: .fit)
            .overlay {
                if let slide, slide.pageIndex == page {
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
            .task(id: Request(cache: ObjectIdentifier(cache), page: page, box: box)) {
                await load()
            }
            .slideOutline()
    }

    private var pageSize: CGSize {
        let sizes = cache.info.pageSizes
        let size = sizes.indices.contains(page) ? sizes[page] : .zero
        let fitted = PageRegion.full.size(onPageOfSize: size)
        return fitted.width > 0 && fitted.height > 0 ? fitted : CGSize(width: 4, height: 3)
    }

    private func load() async {
        guard let box, box.width > 0, box.height > 0 else { return }
        // Resizing the sidebar changes the size many times a second; wait until it settles.
        if slide?.pageIndex == page {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        guard let rendered = try? await cache.thumbnail(page: page, region: .full, fitting: box),
              !Task.isCancelled
        else { return }
        slide = rendered
    }
}
