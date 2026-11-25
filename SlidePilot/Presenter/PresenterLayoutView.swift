import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// The presenter's slots in the session's arrangement (LAY-01 to LAY-03).
struct PresenterLayoutView: View {
    let session: PresentationSession

    /// Optional, so snapshots and previews without settings use the default.
    @Environment(AppSettings.self) private var settings: AppSettings?

    /// The space around each slot, from the Layout settings (LAY-04).
    private var padding: CGFloat {
        (settings?.layoutPadding ?? .default).points
    }

    private var layout: PresenterLayoutModel { session.layout }

    var body: some View {
        let slots = layout.layout.visibleSlots
        let arrangement = layout.arrangement
        Group {
            if session.drawing.isActive {
                // Draw mode replaces the arrangement with the current slide (LAY-08).
                drawingSlot
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        // The slot pickers name the places by the stacked columns (LAY-04). The same test
        // as `TouchSplitView`, which fills this view.
        .onGeometryChange(for: Bool.self) { proxy in
            PresenterSplit.stacksVertically(width: proxy.size.width, height: proxy.size.height, separatorWidth: 1)
        } action: { [layout] isStacked in
            layout.isStacked = isStacked
        }
        #endif
    }

    /// The current slide with the editable drawing on top (DRAW-01). Links are off, the
    /// canvas covers them anyway.
    private var drawingSlot: some View {
        SlideSurface(cache: session.cache, page: session.currentPage, region: session.audienceRegion, role: .current)
            .overlay {
                EditableDrawingLayer(
                    model: session.drawing, page: session.currentPage, region: session.audienceRegion,
                    onEscape: session.stopDrawing
                )
                    // The white canvas would hide the slide's hairline.
                    .slideOutline(session.drawing.drawings.drawing(onPage: session.currentPage).background == .white)
            }
            // The audience still sees where the presenter is about to draw (PTR-01).
            .presenterPointer(session)
            .presenterSlotTitle(.current, position: session.position)
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func slot(_ kind: PresenterSlot) -> some View {
        PresenterSlotView(session: session, kind: kind)
            .presenterSlotTitle(kind, position: session.position)
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The Mac columns host their own views, outside the window's tap area.
            .finishesNotesEditingOnTap(session.notes)
    }

    /// Two slots on top of each other, each half the height (LAY-03).
    private func stack(_ top: PresenterSlot, _ bottom: PresenterSlot) -> some View {
        VStack(spacing: 0) {
            PresenterSlotView(session: session, kind: top)
                .presenterSlotTitle(top, position: session.position)
                .padding([.horizontal, .top], padding)
                .padding(.bottom, padding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .finishesNotesEditingOnTap(session.notes)
            PresenterSlotView(session: session, kind: bottom)
                .presenterSlotTitle(bottom, position: session.position)
                .padding([.horizontal, .bottom], padding)
                .padding(.top, padding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .finishesNotesEditingOnTap(session.notes)
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
            SlideSurface(
                cache: session.cache, page: session.currentPage, region: session.audienceRegion, role: .current,
                pageLinkAction: session.showPage
            )
                .drawingOverlay(session.drawing.drawings, page: session.currentPage, region: session.audienceRegion)
                .presenterPointer(session)
                .slideNavigationForVoiceOver(session)
                .finishesNotesEditing(session)
        case .next:
            NextSlidePreview(
                cache: session.cache, currentPage: session.currentPage, region: session.audienceRegion,
                pageLinkAction: session.showPage, drawings: session.drawing.drawings
            )
                .slideNavigationForVoiceOver(session)
                .finishesNotesEditing(session)
        case .notes:
            if let region = session.splitNotesRegion {
                // The notes half of the current page (NOTES-01, NOTES-02); the drawing
                // belongs to the audience's half, so none is shown here.
                SlideSurface(
                    cache: session.cache, page: session.currentPage, region: region, role: .notes,
                    pageLinkAction: session.showPage
                )
                    .slideNavigationForVoiceOver(session)
            } else {
                NotesEditor(session: session)
            }
        }
    }
}

private extension View {
    /// A click or tap on a slide finishes editing the notes (NOTES-04); links still work.
    /// Only while editing: otherwise the gesture would keep a Mac click from giving the
    /// keyboard to the slides.
    func finishesNotesEditing(_ session: PresentationSession) -> some View {
        simultaneousGesture(
            TapGesture().onEnded { session.notes.finishEditing() },
            isEnabled: session.notes.isEditing
        )
    }

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
