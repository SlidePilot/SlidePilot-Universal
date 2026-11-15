import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// The slide navigator (LAY-06): the sidebar of the presenter's split view, a thumbnail
/// list with a page-number field. Selecting a thumbnail shows that slide. Typing a letter
/// or digit in the list moves it into the field, the typed page is highlighted, and
/// Return jumps to it. Thumbnails do not follow links.
struct SlideNavigator: View {
    let session: PresentationSession

    @State private var pageText = ""
    @FocusState private var isPageFieldFocused: Bool

    private var pageCount: Int { session.cache.info.pageCount }

    private var highlightedPage: Int? {
        NavigatorPageField.page(for: pageText, pageCount: pageCount)
    }

    private var selection: Binding<Int?> {
        Binding {
            session.currentPage
        } set: { page in
            if let page { session.showPage(page) }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(0..<pageCount, id: \.self) { page in
                    NavigatorThumbnail(cache: session.cache, page: page, isHighlighted: page == highlightedPage)
                }
            }
            .listStyle(.sidebar)
            // The old list moved typed letters and digits into the field instead of type-select.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                      press.characters.count == 1,
                      let character = press.characters.first,
                      NavigatorPageField.startsInput(character)
                else { return .ignored }
                pageText = press.characters
                isPageFieldFocused = true
                return .handled
            }
            .searchable(text: $pageText, placement: .sidebar, prompt: Text("Go to Slide"))
            .searchFocused($isPageFieldFocused)
            .onSubmit(of: .search) {
                if let highlightedPage {
                    session.showPage(highlightedPage)
                }
                // The old field selected its text so the next number replaced it.
                pageText = ""
            }
            .onChange(of: highlightedPage) { _, page in
                guard let page else { return }
                withAnimation { proxy.scrollTo(page, anchor: .center) }
            }
            .onChange(of: session.currentPage, initial: true) { _, page in
                proxy.scrollTo(page, anchor: .center)
            }
            #if os(macOS)
            // Like the old app, opening the navigator puts the cursor in the field. Not on
            // iPad, where that would bring up the on-screen keyboard.
            .onAppear { isPageFieldFocused = true }
            #endif
        }
    }
}

/// One slide in the navigator: the thumbnail with its number below, like Preview's sidebar.
private struct NavigatorThumbnail: View {
    let cache: RenderCache
    let page: Int
    /// The page typed in the field, which Return jumps to.
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 4) {
            SlideSurface(cache: cache, page: page, role: .thumbnail)
                .overlay {
                    if isHighlighted {
                        Rectangle().strokeBorder(.tint, lineWidth: 3)
                    }
                }
            Text(page + 1, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHighlighted ? Text("Highlighted") : Text(verbatim: ""))
    }
}
