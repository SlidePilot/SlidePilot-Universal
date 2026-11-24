import SlidePilotCore
import SwiftUI

/// The one-line title above a presenter slot (LAY-10): "Current · 7 / 18", "Next" or
/// "End of Presentation", "Notes".
struct PresenterSlotTitleView: View {
    let title: PresenterSlotTitle

    var body: some View {
        Group {
            switch title {
            case .current(let counter):
                Text("Current · \(counter.number) / \(counter.count)")
                    .accessibilityLabel(Text("Current, Slide \(counter.number) of \(counter.count)"))
            case .next:
                Text("Next", comment: "Title above the next-slide preview in the presenter.")
            case .endOfPresentation:
                Text("End of Presentation", comment: "Title above the next-slide preview after the last slide.")
            case .notes:
                Text("Notes")
            }
        }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsTightening(true)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Puts the slot's title centered above it, like the old app's label (LAY-10).
    func presenterSlotTitle(_ slot: PresenterSlot, position: DeckPosition) -> some View {
        VStack(spacing: 4) {
            PresenterSlotTitleView(title: PresenterSlotTitle(slot: slot, position: position))
            self
        }
    }

    /// The Mac presenter window's subtitle, "Slide 7 of 18" (LAY-10). The iPad has no window
    /// subtitle; the current slot's title shows the counter there.
    func presenterWindowSubtitle(_ position: DeckPosition) -> some View {
        #if os(macOS)
        let counter = SlideCounter(position)
        return navigationSubtitle(Text("Slide \(counter.number) of \(counter.count)"))
        #else
        return self
        #endif
    }
}
