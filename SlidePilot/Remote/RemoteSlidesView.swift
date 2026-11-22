import SlidePilotCore
import SlidePilotRemoteProtocol
import SwiftUI

/// The controlled presentation (REM-07): the slides of the chosen layout, the progress, and
/// the toolbar with slide change, curtain, layout and progress buttons.
///
/// Custom UI (ADR 0010): the slide images are the slide surface and the dot that follows a
/// remote pointer is the pointer overlay; everything else is standard.
struct RemoteSlidesView: View {
    @Environment(AppSettings.self) private var settings
    let control: RemoteControl
    @FocusState private var hasKeyboardFocus: Bool

    private static let previousKeys: Set<KeyEquivalent> = [.leftArrow, .upArrow, .pageUp]
    private static let nextKeys: Set<KeyEquivalent> = [.rightArrow, .downArrow, .pageDown]

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            if settings.remoteShowsProgress, let progress = control.state.progress, let status = control.state.status {
                ProgressView(value: progress) {
                    EmptyView()
                } currentValueLabel: {
                    Text("Slide \(status.slideNumber) of \(status.slideCount)")
                }
                .padding([.horizontal, .top])
            }
            RemoteSlideArea(control: control, layout: settings.remoteControlLayout)
                .padding()
        }
        .overlay {
            if control.connection != .connected {
                ContentUnavailableView {
                    Label {
                        Text("Reconnecting…")
                    } icon: {
                        ProgressView()
                    }
                } description: {
                    Text("Keep SlidePilot open on “\(control.deviceName)”.")
                }
                .background(.background)
            }
        }
        .navigationTitle(control.state.selectedPresentation?.title ?? "")
        .navigationSubtitle(control.deviceName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Previous Slide", systemImage: "chevron.backward") {
                    control.perform(.previousSlide)
                }
                Button("Next Slide", systemImage: "chevron.forward") {
                    control.perform(.nextSlide)
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                curtainMenu
                Menu {
                    Picker("Layout", selection: $settings.remoteControlLayout) {
                        Label("Current and Next Slide", systemImage: "rectangle.split.2x1")
                            .tag(RemoteControlLayout.currentAndNext)
                        Label("Current Slide and Notes", systemImage: "rectangle.and.text.magnifyingglass")
                            .tag(RemoteControlLayout.currentAndNotes)
                        Label("Current Slide", systemImage: "rectangle.center.inset.filled")
                            .tag(RemoteControlLayout.current)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Layout", systemImage: "rectangle.3.group")
                }
                Toggle(isOn: $settings.remoteShowsProgress) {
                    Label("Show Progress", systemImage: "gauge.with.dots.needle.33percent")
                }
            }
        }
        .disabled(control.connection != .connected)
        // Clickers and keyboards: the presenter's keys (NAV-01) and B, W and "." for the
        // curtain (CUR-01).
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        // Escape goes back to the presentations, like the back button.
        .onKeyPress(.escape) {
            control.navigate(to: [.presentations])
            return .handled
        }
        .onKeyPress(keys: Self.previousKeys) { _ in
            control.perform(.previousSlide)
            return .handled
        }
        .onKeyPress(keys: Self.nextKeys) { _ in
            control.perform(.nextSlide)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "bw."), phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            toggleCurtain(press.characters == "w" ? .white : .black)
            return .handled
        }
    }

    private var curtain: RemoteCurtain { control.state.status?.curtain ?? .none }

    /// One tap opens the choices, one more picks off, black or white (REM-07).
    private var curtainMenu: some View {
        Menu {
            Picker("Curtain", selection: curtainBinding) {
                Label("Off", systemImage: "rectangle.dashed")
                    .tag(RemoteCurtain.none)
                Label("Black Screen", systemImage: "rectangle.fill")
                    .tag(RemoteCurtain.black)
                Label("White Screen", systemImage: "rectangle")
                    .tag(RemoteCurtain.white)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Curtain", systemImage: curtainSymbol)
        }
        .accessibilityValue(curtainDescription)
    }

    private var curtainSymbol: String {
        switch curtain {
        case .none: "rectangle.dashed"
        case .black: "rectangle.fill"
        case .white: "rectangle"
        }
    }

    private var curtainDescription: Text {
        switch curtain {
        case .none: Text("Off")
        case .black: Text("Black Screen")
        case .white: Text("White Screen")
        }
    }

    private var curtainBinding: Binding<RemoteCurtain> {
        Binding {
            curtain
        } set: { newCurtain in
            control.perform(.setCurtain(newCurtain))
        }
    }

    private func toggleCurtain(_ color: RemoteCurtain) {
        control.perform(.setCurtain(curtain == color ? .none : color))
    }
}

/// The slides of the layout: side by side in a wide area, stacked in a tall one.
private struct RemoteSlideArea: View {
    @Environment(\.displayScale) private var displayScale
    let control: RemoteControl
    let layout: RemoteControlLayout

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= proxy.size.height
            let spacing = 16.0
            // The current slide gets 60 % of the area when it shares it.
            let share = layout == .current ? 1 : 0.6
            let currentSize = isWide
                ? CGSize(width: (proxy.size.width - (share < 1 ? spacing : 0)) * share, height: proxy.size.height)
                : CGSize(width: proxy.size.width, height: (proxy.size.height - (share < 1 ? spacing : 0)) * share)
            let otherSize = isWide
                ? CGSize(width: proxy.size.width - currentSize.width - spacing, height: proxy.size.height)
                : CGSize(width: proxy.size.width, height: proxy.size.height - currentSize.height - spacing)
            let stack = isWide ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
            stack {
                RemoteCurrentSlide(control: control)
                    .frame(width: currentSize.width, height: currentSize.height)
                    .onChange(of: currentSize, initial: true) { _, size in
                        control.setSlideAreaSize(size, scale: displayScale)
                    }
                if layout != .current {
                    Group {
                        if layout.showsNext {
                            RemoteNextSlide(control: control)
                        } else {
                            RemoteNotesPane(control: control)
                        }
                    }
                    .frame(width: max(otherSize.width, 0), height: max(otherSize.height, 0))
                }
            }
        }
    }
}

/// The current slide: swipe to change slides, pinch to zoom and drag to pan a zoomed slide,
/// double tap and drag for the pointer (REM-07). VoiceOver changes slides with the
/// adjustable action.
private struct RemoteCurrentSlide: View {
    let control: RemoteControl
    @State private var zoom = 1.0
    @State private var zoomAnchor = UnitPoint.center
    @GestureState private var pinch = 1.0
    /// How far a zoomed slide is moved, without the running pan.
    @State private var pan = CGSize.zero
    @State private var panDrag = CGSize.zero
    @State private var isPanning = false
    @State private var imageSize = CGSize.zero
    /// Where the controller's pointer is, while it moves.
    @State private var pointer: CGPoint?

    var body: some View {
        RemoteSlideImage(image: control.slides?.current, isLoading: control.slides == nil, aspectRatio: aspectRatio)
            .overlay { curtainOverlay }
            .overlay(alignment: .topLeading) {
                if let pointer {
                    // Shows where the pointer is on the host.
                    Circle()
                        .fill(.red)
                        .frame(width: 14, height: 14)
                        .offset(x: pointer.x - 7, y: pointer.y - 7)
                        .accessibilityHidden(true)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { imageSize = $0 }
            .contentShape(.rect)
            .gesture(drag)
            .simultaneousGesture(magnify)
            .scaleEffect(zoom * pinch, anchor: zoomAnchor)
            .offset(clampedPan(CGSize(width: pan.width + panDrag.width, height: pan.height + panDrag.height)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Measured outside the zoomed slide, so the slide follows the finger.
            .simultaneousGesture(panGesture)
            .onChange(of: control.slides?.slideIndex) {
                zoom = 1
                pan = .zero
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Current Slide"))
            .accessibilityValue(slideValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: control.perform(.nextSlide)
                case .decrement: control.perform(.previousSlide)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Next Slide")) { control.perform(.nextSlide) }
            .accessibilityAction(named: Text("Previous Slide")) { control.perform(.previousSlide) }
    }

    private var aspectRatio: CGFloat? {
        control.slides?.current.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) }
    }

    private var slideValue: Text {
        guard let status = control.state.status else { return Text(verbatim: "") }
        return Text("Slide \(status.slideNumber) of \(status.slideCount)")
    }

    @ViewBuilder private var curtainOverlay: some View {
        switch control.state.status?.curtain ?? .none {
        case .none:
            EmptyView()
        case .black:
            // What the audience sees: the slide surface shows the curtain's color.
            Color.black.opacity(0.85)
                .overlay { Label("Black Screen", systemImage: "rectangle.fill").foregroundStyle(.white) }
        case .white:
            Color.white.opacity(0.85)
                .overlay { Label("White Screen", systemImage: "rectangle").foregroundStyle(.black) }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isPanning else { return }
                control.touchMoved(start: value.startLocation, location: value.location, time: value.time, slideSize: imageSize)
                pointer = control.isMovingPointer ? clamped(value.location) : nil
            }
            .onEnded { value in
                control.touchEnded(start: value.startLocation, location: value.location, time: value.time)
                pointer = nil
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onChanged { value in
                if pinch == 1 {
                    zoomAnchor = value.startAnchor
                    control.cancelTouch()
                    pointer = nil
                }
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 1), 5)
                pan = clampedPan(pan)
            }
    }

    /// A zoomed slide moves with a drag that does not move the pointer; the drag is then no
    /// swipe.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: RemoteGestureInterpreter.tapMovement, coordinateSpace: .global)
            .onChanged { value in
                guard zoom > 1, !control.isMovingPointer else { return }
                if !isPanning {
                    isPanning = true
                    control.cancelTouch()
                    pointer = nil
                }
                panDrag = value.translation
            }
            .onEnded { _ in
                guard isPanning else { return }
                pan = clampedPan(CGSize(width: pan.width + panDrag.width, height: pan.height + panDrag.height))
                panDrag = .zero
                isPanning = false
            }
    }

    /// Keeps the zoomed slide covering its area.
    private func clampedPan(_ offset: CGSize) -> CGSize {
        let scale = zoom * pinch
        guard scale > 1 else { return .zero }
        func clamp(_ value: CGFloat, length: CGFloat, anchor: CGFloat) -> CGFloat {
            let lower = length * (1 - scale) * (1 - anchor)
            let upper = length * (scale - 1) * anchor
            return min(max(value, lower), upper)
        }
        return CGSize(
            width: clamp(offset.width, length: imageSize.width, anchor: zoomAnchor.x),
            height: clamp(offset.height, length: imageSize.height, anchor: zoomAnchor.y)
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }
}

/// The next slide; black after the last slide, like the presenter (REM-04).
private struct RemoteNextSlide: View {
    let control: RemoteControl

    var body: some View {
        let slides = control.slides
        let isEnd = slides != nil && slides?.next == nil
        RemoteSlideImage(image: slides?.next, isLoading: slides == nil, aspectRatio: slides?.current.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Next Slide"))
            .accessibilityValue(isEnd ? Text("End of presentation") : Text(verbatim: ""))
    }
}

/// The notes of the current slide: the notes half in split notes mode, then the text.
private struct RemoteNotesPane: View {
    let control: RemoteControl

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let notesImage = control.slides?.notes {
                    Image(decorative: notesImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                if let notes = control.notes {
                    Text(notes)
                        .textSelection(.enabled)
                } else if control.slides?.notes == nil {
                    Text("No Notes")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notes"))
    }
}

/// One slide image fitted into its slot. Black without an image (after the last slide);
/// a spinner while the first images load.
private struct RemoteSlideImage: View {
    let image: CGImage?
    let isLoading: Bool
    let aspectRatio: CGFloat?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .slideOutline()
            } else if isLoading {
                Rectangle()
                    .fill(.quaternary)
                    .overlay { ProgressView() }
            } else {
                // The slide surface after the last slide (black, as in the presenter).
                Color.black
            }
        }
        .aspectRatio(aspectRatio ?? 4 / 3, contentMode: .fit)
    }
}
