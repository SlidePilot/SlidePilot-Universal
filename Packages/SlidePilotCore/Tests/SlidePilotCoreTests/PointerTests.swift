import CoreGraphics
import Foundation
import SlidePilotCore
import Testing

@Suite @MainActor
struct PointerStateTests {
    private let slide = CGSize(width: 400, height: 300)

    @Test func startsHiddenWithTheCursor() {
        let pointer = PointerState()
        #expect(!pointer.isShown)
        #expect(pointer.appearance == .cursor)
        #expect(pointer.visibleLocation(remote: nil) == nil)
    }

    @Test func movesRelativeToTheSlide() {
        let pointer = PointerState(isShown: true)
        pointer.presenterMoved(to: CGPoint(x: 100, y: 150), inSlideOfSize: slide)
        #expect(pointer.visibleLocation(remote: nil) == CGPoint(x: 0.25, y: 0.5))
    }

    // PTR-01: outside 0…1 the pointer hides; the edges still count as on the slide.
    @Test func hidesOutsideTheSlide() {
        let pointer = PointerState(isShown: true)
        pointer.presenterMoved(to: CGPoint(x: 400, y: 0), inSlideOfSize: slide)
        #expect(pointer.presenterLocation == CGPoint(x: 1, y: 0))
        pointer.presenterMoved(to: CGPoint(x: 401, y: 10), inSlideOfSize: slide)
        #expect(pointer.presenterLocation == nil)
        pointer.presenterMoved(to: CGPoint(x: 10, y: -1), inSlideOfSize: slide)
        #expect(pointer.presenterLocation == nil)
        pointer.presenterMoved(to: CGPoint(x: 10, y: 10), inSlideOfSize: .zero)
        #expect(pointer.presenterLocation == nil)
    }

    @Test func endingHidesThePresentersPointer() {
        let pointer = PointerState(isShown: true)
        pointer.presenterMoved(to: CGPoint(x: 10, y: 10), inSlideOfSize: slide)
        pointer.presenterEnded()
        #expect(pointer.visibleLocation(remote: nil) == nil)
    }

    @Test func doesNotFollowWhileHidden() {
        let pointer = PointerState()
        pointer.presenterMoved(to: CGPoint(x: 10, y: 10), inSlideOfSize: slide)
        #expect(pointer.presenterLocation == nil)
    }

    @Test func hidingForgetsTheLocation() {
        let pointer = PointerState(isShown: true)
        pointer.presenterMoved(to: CGPoint(x: 10, y: 10), inSlideOfSize: slide)
        pointer.isShown = false
        pointer.isShown = true
        #expect(pointer.visibleLocation(remote: nil) == nil)
    }

    // DEF-14: the old app showed the remote's pointer even while the pointer was hidden.
    @Test func remotePointerOnlyWhileShown() {
        let remote = CGPoint(x: 0.3, y: 0.7)
        let pointer = PointerState()
        #expect(pointer.visibleLocation(remote: remote) == nil)
        pointer.isShown = true
        #expect(pointer.visibleLocation(remote: remote) == remote)
        #expect(pointer.visibleLocation(remote: CGPoint(x: 1.2, y: 0.5)) == nil)
    }

    @Test func presenterWinsOverRemote() {
        let pointer = PointerState(isShown: true)
        pointer.presenterMoved(to: CGPoint(x: 200, y: 150), inSlideOfSize: slide)
        #expect(pointer.visibleLocation(remote: CGPoint(x: 0.1, y: 0.1)) == CGPoint(x: 0.5, y: 0.5))
    }
}

@Suite
struct PointerAppearanceTests {
    // PTR-02: the old menu's order defines ⌘1…⌘7.
    @Test func menuOrderAndShortcuts() {
        #expect(PointerAppearance.allCases == [.cursor, .hand, .dot, .circle, .targetBlack, .targetRed, .individual])
        #expect(PointerAppearance.allCases.map(\.shortcutDigit) == Array(1...7))
    }

    @Test func presetsMatchTheOldApp() {
        let individual = PointerConfiguration(shape: .square, size: 30, color: .white)
        #expect(PointerAppearance.cursor.configuration(individual: individual).shape == .cursor)
        #expect(PointerAppearance.hand.configuration(individual: individual).shape == .hand)
        #expect(PointerAppearance.individual.configuration(individual: individual) == individual)

        let target = PointerAppearance.targetBlack.configuration(individual: individual)
        #expect(target == PointerConfiguration(
            shape: .target, size: 44, thickness: 3, color: .black, borderWidth: 2, borderColor: .white
        ))
        let red = PointerAppearance.targetRed.configuration(individual: individual)
        #expect(red.shape == .target && red.size == 44 && red.thickness == 3 && red.borderWidth == 0)
        #expect(red.color == .red)
        let circle = PointerAppearance.circle.configuration(individual: individual)
        #expect(circle == PointerConfiguration(shape: .circle, size: 20, thickness: 3, color: .white, shadowWidth: 10))
        let dot = PointerAppearance.dot.configuration(individual: individual)
        #expect(dot == PointerConfiguration(
            shape: .dot, size: 10, color: .black, borderWidth: 5, borderColor: .white, shadowWidth: 10
        ))
    }

    @Test func configurationRoundTripsAsJSON() throws {
        let configuration = PointerConfiguration(
            shape: .cross, size: 30, thickness: 4, color: PointerColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            borderWidth: 1, borderColor: .white, shadowWidth: 2
        )
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(PointerConfiguration.self, from: data) == configuration)
    }
}

@Suite
struct PointerDrawingTests {
    @Test func systemImagesAreNotDrawn() {
        #expect(PointerDrawing(.cursor) == nil)
        #expect(PointerDrawing(.hand) == nil)
    }

    // Target: center dot with border, ring border and ring (PointerView.swift:166-208).
    @Test func targetLayout() throws {
        #expect(PointerDrawing(.target)?.side == 49)
        let configuration = PointerConfiguration(
            shape: .target, size: 40, thickness: 5, color: .black, borderWidth: 2, borderColor: .white
        )
        let drawing = try #require(PointerDrawing(configuration))
        #expect(drawing.side == 47)
        #expect(drawing.shadowRadius == 0)
        #expect(drawing.parts == [
            .fillEllipse(CGRect(x: 18, y: 18, width: 11, height: 11), .white),
            .fillEllipse(CGRect(x: 20, y: 20, width: 7, height: 7), .black),
            .strokeEllipse(CGRect(x: 1, y: 1, width: 45, height: 45), lineWidth: 2, .white),
            .strokeEllipse(CGRect(x: 4.5, y: 4.5, width: 38, height: 38), lineWidth: 5, .black),
        ])
    }

    @Test func targetWithoutBorderHasNoBorderParts() throws {
        let drawing = try #require(PointerDrawing(.targetRed))
        #expect(drawing.side == 47)
        #expect(drawing.parts.count == 2)
    }

    @Test func circleLeavesRoomForItsShadow() throws {
        let drawing = try #require(PointerDrawing(.circle))
        #expect(drawing.side == 20 + 3 + 35)
        #expect(drawing.shadowRadius == 10)
        #expect(drawing.parts == [
            .strokeEllipse(CGRect(x: 19, y: 19, width: 20, height: 20), lineWidth: 3, .white),
        ])
    }

    @Test func dotLayout() throws {
        let drawing = try #require(PointerDrawing(.dot))
        #expect(drawing.side == 10 + 5 + 35)
        #expect(drawing.parts == [
            .fillEllipse(CGRect(x: 17.5, y: 17.5, width: 15, height: 15), .white),
            .fillEllipse(CGRect(x: 20, y: 20, width: 10, height: 10), .black),
        ])
    }

    @Test func crossIsARotatedPlus() throws {
        let plus = try #require(PointerDrawing(PointerConfiguration(shape: .plus, size: 20, thickness: 4)))
        let cross = try #require(PointerDrawing(PointerConfiguration(shape: .cross, size: 20, thickness: 4)))
        #expect(plus.rotation == 0)
        #expect(cross.rotation == 45)
        #expect(plus.parts == cross.parts)
        #expect(plus.parts == [
            .fillRect(CGRect(x: 8, y: 0, width: 4, height: 20), .black),
            .fillRect(CGRect(x: 0, y: 8, width: 20, height: 4), .black),
        ])
    }

    @Test func squareWithBorder() throws {
        let drawing = try #require(PointerDrawing(
            PointerConfiguration(shape: .square, size: 20, color: .white, borderWidth: 4, borderColor: .black)
        ))
        #expect(drawing.side == 24)
        #expect(drawing.parts == [
            .fillRect(CGRect(x: 0, y: 0, width: 24, height: 24), .black),
            .fillRect(CGRect(x: 2, y: 2, width: 20, height: 20), .white),
        ])
    }
}

@Suite
struct PointerSettingsTests {
    @Test func pointerSettingsRoundTrip() throws {
        let settings = DocumentSettings(isPointerDisplayed: true, pointerAppearance: .targetRed)
        #expect(!settings.isEmpty)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DocumentSettings.self, from: data)
        #expect(decoded.isPointerDisplayed == true)
        #expect(decoded.pointerAppearance == .targetRed)
    }

    @Test func unknownAppearanceFallsBackToNotSaved() throws {
        let json = Data(#"{"isPointerDisplayed": true, "pointerAppearance": "laser", "isNavigatorDisplayed": true}"#.utf8)
        let decoded = try JSONDecoder().decode(DocumentSettings.self, from: json)
        #expect(decoded.pointerAppearance == nil)
        #expect(decoded.isPointerDisplayed == true)
        #expect(decoded.isNavigatorDisplayed == true)
    }
}
