import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// The presenter's slots in the session's arrangement (LAY-01 to LAY-03).
struct PresenterLayoutView: View {
    let session: PresentationSession

    /// The old app's default layout padding; the Layout settings (#16) make it adjustable.
    private let padding: CGFloat = 30

    private var layout: PresenterLayoutModel { session.layout }

    var body: some View {
        let slots = layout.layout.visibleSlots
        let arrangement = layout.arrangement
        Group {
            switch arrangement {
            case .single:
                slot(slots[0])
            case .double:
                columns(arrangement) {
                    slot(slots[0])
                } trailing: {
                    slot(slots[1])
                }
            case .tripleLeft:
                columns(arrangement) {
                    slot(slots[2])
                } trailing: {
                    stack(slots[0], slots[1])
                }
            case .tripleRight:
                columns(arrangement) {
                    stack(slots[0], slots[1])
                } trailing: {
                    slot(slots[2])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func slot(_ kind: PresenterSlot) -> some View {
        PresenterSlotView(session: session, kind: kind)
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Two slots on top of each other, each half the height (LAY-03).
    private func stack(_ top: PresenterSlot, _ bottom: PresenterSlot) -> some View {
        VStack(spacing: 0) {
            PresenterSlotView(session: session, kind: top)
                .padding([.horizontal, .top], padding)
                .padding(.bottom, padding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PresenterSlotView(session: session, kind: bottom)
                .padding([.horizontal, .bottom], padding)
                .padding(.top, padding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func columns<Leading: View, Trailing: View>(
        _ arrangement: PresenterArrangement,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let fraction = layout.leadingFraction(in: arrangement)
        let onDrag = { [layout] (fraction: Double) in layout.setLeadingFraction(fraction, in: arrangement) }
        #if os(macOS)
        MacSplitView(fraction: fraction, onDrag: onDrag, leading: leading, trailing: trailing)
            .frame(minWidth: 2 * PresenterSplit.minimumColumnWidth + 1)
        #else
        TouchSplitView(fraction: fraction, onDrag: onDrag, leading: leading, trailing: trailing)
        #endif
    }
}

/// One slot. It reads the session itself, so every visible slot follows slide changes,
/// also when the current slide is hidden (DEF-16).
private struct PresenterSlotView: View {
    let session: PresentationSession
    let kind: PresenterSlot

    var body: some View {
        switch kind {
        case .current:
            SlideSurface(cache: session.cache, page: session.currentPage, role: .current)
                .slideNavigationForVoiceOver(session)
        case .next:
            NextSlidePreview(cache: session.cache, currentPage: session.currentPage)
                .slideNavigationForVoiceOver(session)
        case .notes:
            // Until the notes editor (#27) and split notes (#28).
            ContentUnavailableView("No Notes", systemImage: "note.text")
        }
    }
}

private extension View {
    /// VoiceOver users without a keyboard swipe up or down on a slide to change slides.
    func slideNavigationForVoiceOver(_ session: PresentationSession) -> some View {
        accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: session.showNextPage()
            case .decrement: session.showPreviousPage()
            @unknown default: break
            }
        }
    }
}
