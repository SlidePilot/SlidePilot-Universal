import PDFKit
import SlidePilotCore
import SwiftUI
import Testing
@testable import SlidePilot

/// Mac screenshots for PRs, rendered by the app itself (see `WindowSnapshot`).
///
/// Not part of the default test plan. Run the `SlidePilotMacSnapshots` scheme and
/// export the PNGs with `scripts/export-mac-snapshots.py`.
/// Use fixtures only, never personal documents.
@Suite(.serialized)
struct MacSnapshots {
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func firstSlide(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        try await WindowSnapshot.record(DocumentView(document: document, layoutStore: InMemoryPresenterLayoutStore()).snapshotScene(), name: "slides-first", appearance: appearance)
    }

    // LAY-09: after the last slide the preview shows the end-of-deck page.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func lastSlide(appearance: WindowSnapshot.Appearance) async throws {
        let data = try Fixture.data("plain-slides.pdf")
        let pdf = try #require(PDFDocument(data: data))
        let document = try PDFFileDocument(data: data)
        let view = DocumentView(document: document, page: pdf.pageCount - 1, layoutStore: InMemoryPresenterLayoutStore()).snapshotScene()
        try await WindowSnapshot.record(view, name: "slides-last", appearance: appearance)
    }

    // DOC-08: a copy of a 6-page deck is open on slide 6 and is rewritten in place with a
    // 4-page deck (like pdflatex), then replaced atomically with the 6-page deck again.
    // Expected: slide 4 of 4 with the end-of-deck page, then slide 4 of 6 with slide 5 next.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func reloadAfterRecompile(appearance: WindowSnapshot.Appearance) async throws {
        let long = try Fixture.data("rotated.pdf")
        let short = try Fixture.data("media.pdf")
        let folder = FileManager.default.temporaryDirectory.appending(path: "reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "slides.pdf")
        try long.write(to: url)

        let view = DocumentView(document: try PDFFileDocument(data: long), fileURL: url, page: 5, layoutStore: InMemoryPresenterLayoutStore(), companionStore: nil).snapshotScene()
        let window = WindowSnapshot.makeWindow(view, appearance: appearance)
        defer { window.close() }
        // Let the file presenter register before the first change.
        try await Task.sleep(for: .seconds(1))

        try short.write(to: url)
        try await Task.sleep(for: .seconds(4))
        try await WindowSnapshot.record(window, name: "reload-shorter-\(appearance.rawValue)")

        try long.write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(4))
        try await WindowSnapshot.record(window, name: "reload-longer-\(appearance.rawValue)")
    }

    // NAV-03: after a slide change the Go Back toolbar button is enabled.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func goBackEnabled(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        let session = PresentationSession(data: document.data, info: document.info, layoutStore: InMemoryPresenterLayoutStore())
        session.showNextPage()
        let view = PresenterLayoutView(session: session).presenterNavigation(session)
        try await WindowSnapshot.record(view, name: "go-back-enabled", appearance: appearance)
    }

    // DOC-04: the presentation window shows the current slide on black.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func presentation(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        let session = PresentationSession(data: document.data, info: document.info, page: 1, layoutStore: InMemoryPresenterLayoutStore())
        let view = PresentationView(session: session)
        try await WindowSnapshot.record(view, name: "presentation", size: CGSize(width: 960, height: 600), appearance: appearance)
    }

    // CUR-01, CUR-02: the presenter with a white curtain (toggled button and "Screen is
    // hidden" in the title bar) and the presentation covered in white.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func curtain(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        let session = PresentationSession(data: document.data, info: document.info, page: 1, layoutStore: InMemoryPresenterLayoutStore())
        session.curtain = .white
        let presenter = PresenterLayoutView(session: session).presenterCurtain(session)
        try await WindowSnapshot.record(presenter, name: "curtain-presenter", size: CGSize(width: 1200, height: 700), appearance: appearance)
        try await WindowSnapshot.record(PresentationView(session: session), name: "curtain-presentation", size: CGSize(width: 960, height: 600), appearance: appearance)
    }

    // TIME-01 to TIME-03, TIME-06: clock with a running stopwatch (normal size) and a timer
    // in overtime (small size).
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func timeDisplay(appearance: WindowSnapshot.Appearance) async throws {
        var stopwatch = PresentationTimer()
        stopwatch.toggle(at: .now.addingTimeInterval(-754))
        var timer = PresentationTimer(mode: .timer)
        timer.setTimerDuration(60)
        timer.toggle(at: .now.addingTimeInterval(-125))
        let view = VStack(alignment: .leading, spacing: 20) {
            TimeDisplay(timer: stopwatch, size: .normal)
            TimeDisplay(timer: timer, size: .small)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        try await WindowSnapshot.record(view, name: "time-display", size: CGSize(width: 1000, height: 300), appearance: appearance)
    }

    // TIME-03: the Set Timer sheet.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func setTimer(appearance: WindowSnapshot.Appearance) async throws {
        let view = SetTimerSheet(duration: 20 * 60) { _ in }
        try await WindowSnapshot.record(view, name: "set-timer", size: CGSize(width: 480, height: 300), appearance: appearance)
    }

    // DOC-05 (iPad): the external display while no document is open. Rendered on the Mac
    // to check the logo and text; the iPad shows the same view.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func readyToPresent(appearance: WindowSnapshot.Appearance) async throws {
        try await WindowSnapshot.record(ReadyToPresentView(), name: "ready-to-present", size: CGSize(width: 960, height: 540), appearance: appearance)
    }
}

extension MacSnapshots {
    // LAY-01 to LAY-03: each arrangement. Triple left is the default layout after showing
    // the notes (N); triple right and single are chosen in View ▸ Arrangement; two slides
    // shows a moved separator.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func arrangements(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        var tripleLeft = PresenterLayout.default
        tripleLeft.setVisible(.notes, true)
        var tripleRight = PresenterLayout(arrangement: .tripleRight)
        tripleRight.setLeadingFraction(0.45, in: .tripleRight)
        var double = PresenterLayout.default
        double.setLeadingFraction(0.7, in: .double)
        let layouts: [(String, PresenterLayout)] = [
            ("layout-triple-left", tripleLeft),
            ("layout-triple-right", tripleRight),
            ("layout-double-moved", double),
            ("layout-single", PresenterLayout(arrangement: .single)),
        ]
        for (name, layout) in layouts {
            let store = InMemoryPresenterLayoutStore(layout: layout)
            let view = DocumentView(document: document, page: 1, layoutStore: store).snapshotScene()
            try await WindowSnapshot.record(view, name: name, size: CGSize(width: 1200, height: 700), appearance: appearance)
        }
    }

    // LAY-06: the navigator's list with slide 3 selected. Snapshots of the whole split view
    // leave the sidebar empty (it is drawn in its own layer), so this shows the list alone.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func navigatorList(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        let session = PresentationSession(data: document.data, info: document.info, page: 2, layoutStore: InMemoryPresenterLayoutStore())
        let view = NavigationStack {
            SlideNavigator(session: session, closesOnSelection: false)
        }
        let window = WindowSnapshot.makeWindow(view, size: CGSize(width: 240, height: 650), appearance: appearance)
        defer { window.close() }
        try await Task.sleep(for: .seconds(2))
        try await WindowSnapshot.record(window, name: "navigator-list-\(appearance.rawValue)")
    }

    // SET-01, SET-05: the General pane of the Settings window, Keep awake on. Only the pane:
    // the window's tab bar is not drawn outside a Settings scene.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func settingsGeneral(appearance: WindowSnapshot.Appearance) async throws {
        let settings = AppSettings(store: InMemorySettingsStore(values: [AppSettings.Key.keepsDisplayAwake: true]))
        let view = SettingsPane { GeneralSettingsView() }.environment(settings)
        try await WindowSnapshot.record(view, name: "settings-general", size: CGSize(width: 500, height: 160), appearance: appearance)
    }
}

private extension View {
    /// The environment the app's scenes provide.
    func snapshotScene() -> some View {
        environment(SessionRegistry()).environment(MacPresentationWindows())
    }
}
