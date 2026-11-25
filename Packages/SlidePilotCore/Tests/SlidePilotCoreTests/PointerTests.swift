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

    // PTR-01 (product-owner decision 2026-11-25): a finger points with double tap and
    // hold whether or not the pointer is shown; lifting it hides the pointer again.
    @Test func touchPointsWhileTheToggleIsOff() {
        let pointer = PointerState()
        pointer.touchMoved(to: CGPoint(x: 100, y: 150), inSlideOfSize: slide)
        #expect(pointer.isTouchPointing)
        #expect(pointer.visibleLocation(remote: nil) == CGPoint(x: 0.25, y: 0.5))
        pointer.touchMoved(to: CGPoint(x: 200, y: 150), inSlideOfSize: slide)
        #expect(pointer.visibleLocation(remote: nil) == CGPoint(x: 0.5, y: 0.5))
        pointer.touchEnded()
        #expect(!pointer.isTouchPointing)
        #expect(pointer.visibleLocation(remote: nil) == nil)
        #expect(!pointer.isShown)
    }

    @Test func touchHidesOutsideTheSlideUntilItComesBack() {
        let pointer = PointerState()
        pointer.touchMoved(to: CGPoint(x: 500, y: 150), inSlideOfSize: slide)
        #expect(pointer.isTouchPointing)
        #expect(pointer.visibleLocation(remote: nil) == nil)
        pointer.touchMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide)
        #expect(pointer.visibleLocation(remote: nil) == .zero)
    }

    @Test func touchWinsOverHoverAndRemote() {
        let pointer = PointerState(isShown: true)
        pointer.touchMoved(to: CGPoint(x: 200, y: 150), inSlideOfSize: slide)
        // Hover reports (Pencil, trackpad) do not move or end a held pointer.
        pointer.presenterMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide)
        pointer.presenterEnded()
        #expect(pointer.visibleLocation(remote: CGPoint(x: 0.1, y: 0.1)) == CGPoint(x: 0.5, y: 0.5))
        pointer.touchEnded()
        #expect(pointer.visibleLocation(remote: CGPoint(x: 0.1, y: 0.1)) == CGPoint(x: 0.1, y: 0.1))
    }

    @Test func touchKeepsPointingWhenTheToggleTurnsOff() {
        let pointer = PointerState(isShown: true)
        pointer.touchMoved(to: CGPoint(x: 200, y: 150), inSlideOfSize: slide)
        pointer.isShown = false
        #expect(pointer.visibleLocation(remote: nil) == CGPoint(x: 0.5, y: 0.5))
        // The remote's pointer stays hidden while the toggle is off (DEF-14).
        pointer.touchMoved(to: CGPoint(x: 500, y: 150), inSlideOfSize: slide)
        #expect(pointer.visibleLocation(remote: CGPoint(x: 0.1, y: 0.1)) == nil)
    }
}

@Suite("Double tap and hold (PTR-01, REM-07)")
struct DoubleTapHoldGestureTests {
    private let point = CGPoint(x: 100, y: 100)

    private func tap(_ gesture: inout DoubleTapHoldGesture, at point: CGPoint, time: Double) {
        gesture.began(at: point, time: time)
        gesture.ended(at: point, time: time + 0.1)
    }

    @Test func aSingleTouchDoesNotHold() {
        var gesture = DoubleTapHoldGesture()
        let result1 = gesture.began(at: point, time: 0)
        #expect(!result1)
        #expect(!gesture.isHolding)
        #expect(gesture.isTracking)
        gesture.ended(at: point, time: 0.1)
        #expect(!gesture.isTracking)
    }

    @Test func secondTouchAfterATapHolds() {
        var gesture = DoubleTapHoldGesture()
        tap(&gesture, at: point, time: 0)
        let result2 = gesture.began(at: CGPoint(x: 110, y: 95), time: 0.4)
        #expect(result2)
        #expect(gesture.isHolding)
        gesture.ended(at: CGPoint(x: 400, y: 300), time: 3)
        #expect(!gesture.isHolding)
    }

    @Test func doubleTapTimingLimits() {
        var gesture = DoubleTapHoldGesture()
        // The second touch starts at most `doubleTapInterval` after the first tap ended.
        tap(&gesture, at: point, time: 0)
        let result3 = gesture.began(at: point, time: 0.1 + DoubleTapHoldGesture.doubleTapInterval)
        #expect(result3)
        gesture.ended(at: point, time: 1)

        tap(&gesture, at: point, time: 2)
        let result4 = gesture.began(at: point, time: 2.1 + DoubleTapHoldGesture.doubleTapInterval + 0.01)
        #expect(!result4)
    }

    @Test func aLongFirstTouchIsNoTap() {
        var gesture = DoubleTapHoldGesture()
        gesture.began(at: point, time: 0)
        gesture.ended(at: point, time: DoubleTapHoldGesture.tapDuration + 0.01)
        let result5 = gesture.began(at: point, time: 0.4)
        #expect(!result5)
    }

    @Test func aMovedFirstTouchIsNoTap() {
        var gesture = DoubleTapHoldGesture()
        // A swipe is no first tap, so a swipe followed by a touch does not point.
        gesture.began(at: point, time: 0)
        gesture.ended(at: CGPoint(x: 100 + DoubleTapHoldGesture.tapMovement, y: 100), time: 0.1)
        let result6 = gesture.began(at: point, time: 0.2)
        #expect(!result6)
    }

    @Test func aDistantSecondTouchDoesNotHold() {
        var gesture = DoubleTapHoldGesture()
        tap(&gesture, at: point, time: 0)
        let result7 = gesture.began(at: CGPoint(x: 100, y: 100 + DoubleTapHoldGesture.doubleTapDistance + 1), time: 0.2)
        #expect(!result7)
    }

    @Test func aTripleTapHoldsOnlyOnce() {
        var gesture = DoubleTapHoldGesture()
        tap(&gesture, at: point, time: 0)
        tap(&gesture, at: point, time: 0.2)
        let result8 = gesture.began(at: point, time: 0.4)
        #expect(!result8)
    }

    @Test func cancelEndsTheHoldAndForgetsTheTap() {
        var gesture = DoubleTapHoldGesture()
        tap(&gesture, at: point, time: 0)
        gesture.began(at: point, time: 0.2)
        let result9 = gesture.cancel()
        #expect(result9)
        #expect(!gesture.isHolding)
        #expect(!gesture.isTracking)
        let result10 = gesture.cancel()
        #expect(!result10)
        gesture.ended(at: point, time: 0.25)
        let result11 = gesture.began(at: point, time: 0.3)
        #expect(!result11)

        // A cancelled first tap is no tap either.
        gesture.ended(at: point, time: 0.35)
        gesture.began(at: point, time: 1)
        let result12 = gesture.cancel()
        #expect(!result12)
        gesture.ended(at: point, time: 1.05)
        let result13 = gesture.began(at: point, time: 1.1)
        #expect(!result13)
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

@Suite
struct PointerEditorTests {
    // PTR-04: the old editor's shapes, in its order.
    @Test func offersTheOldShapes() {
        #expect(PointerShape.editorShapes == [.target, .dot, .circle, .plus, .cross, .square])
        #expect(PointerShape.cursor.editorLimits == nil)
        #expect(PointerShape.hand.editorLimits == nil)
    }

    // PTR-04: target 35–150 and thickness 2–50; other shapes 5–100; dot and square have
    // no thickness; border and shadow 0–50.
    @Test func usesTheOldRanges() throws {
        let target = try #require(PointerShape.target.editorLimits)
        #expect(target.size == 35...150)
        #expect(target.thickness == 2...50)
        for shape in [PointerShape.circle, .plus, .cross] {
            let limits = try #require(shape.editorLimits)
            #expect(limits.size == 5...100)
            #expect(limits.thickness == 2...50)
        }
        for shape in [PointerShape.dot, .square] {
            let limits = try #require(shape.editorLimits)
            #expect(limits.size == 5...100)
            #expect(limits.thickness == nil)
        }
        for shape in PointerShape.editorShapes {
            let limits = try #require(shape.editorLimits)
            #expect(limits.borderWidth == 0...50)
            #expect(limits.shadowWidth == 0...50)
        }
    }

    // DEF-14: changing the shape keeps the values instead of resetting them.
    @Test func changingTheShapeKeepsTheValues() {
        let pointer = PointerConfiguration(
            shape: .target, size: 60, thickness: 8, color: .red, borderWidth: 4, borderColor: .white, shadowWidth: 12
        )
        let circle = pointer.withShape(.circle)
        #expect(circle == PointerConfiguration(
            shape: .circle, size: 60, thickness: 8, color: .red, borderWidth: 4, borderColor: .white, shadowWidth: 12
        ))
        // Back again: nothing lost.
        #expect(circle.withShape(.target) == pointer)
    }

    @Test func changingTheShapeMovesValuesIntoItsRanges() {
        let dot = PointerConfiguration(shape: .dot, size: 10, color: .black, borderWidth: 5, borderColor: .white, shadowWidth: 10)
        let target = dot.withShape(.target)
        #expect(target.size == 35)
        #expect(target.thickness == 2)
        #expect(target.borderWidth == 5)
        #expect(target.shadowWidth == 10)
        let big = PointerConfiguration(shape: .target, size: 150, thickness: 3)
        #expect(big.withShape(.plus).size == 100)
    }

    // Dot and square ignore the thickness, so it is kept for the next shape.
    @Test func shapesWithoutThicknessKeepIt() {
        let pointer = PointerConfiguration(shape: .circle, size: 20, thickness: 7)
        #expect(pointer.withShape(.square).thickness == 7)
        #expect(pointer.withShape(.square).withShape(.circle).thickness == 7)
    }

    @Test func clampsHandEditedValues() {
        let pointer = PointerConfiguration(
            shape: .cross, size: .nan, thickness: 500,
            color: PointerColor(red: 2, green: -1, blue: 0.5, alpha: 3), borderWidth: -4, shadowWidth: 80
        )
        let clamped = pointer.clampedForEditor()
        #expect(clamped.size == 5)
        #expect(clamped.thickness == 50)
        #expect(clamped.borderWidth == 0)
        #expect(clamped.shadowWidth == 50)
        #expect(clamped.color == PointerColor(red: 1, green: 0, blue: 0.5, alpha: 1))
    }

    // The editor cannot show the system images; such a stored pointer becomes Target.
    @Test func systemImagesBecomeTheDefault() {
        #expect(PointerConfiguration.hand.clampedForEditor() == .defaultIndividual)
        #expect(PointerConfiguration.hand.withShape(.cursor) == .defaultIndividual)
    }

    @Test func presetsFitTheEditor() {
        for preset in [PointerConfiguration.target, .targetRed, .circle, .dot] {
            #expect(preset.clampedForEditor() == preset)
        }
    }
}

@Suite
struct PointerColorTests {
    // PTR-05: colors are stored as sRGB components with alpha.
    @Test func convertsFromAndToCGColor() throws {
        let color = PointerColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        let roundTrip = try #require(PointerColor(color.cgColor))
        #expect(abs(roundTrip.red - 0.2) < 0.0001)
        #expect(abs(roundTrip.green - 0.4) < 0.0001)
        #expect(abs(roundTrip.blue - 0.6) < 0.0001)
        #expect(abs(roundTrip.alpha - 0.5) < 0.0001)
    }

    @Test func convertsGrayToSRGB() throws {
        let gray = CGColor(gray: 1, alpha: 0.25)
        let color = try #require(PointerColor(gray))
        #expect(abs(color.red - 1) < 0.0001)
        #expect(abs(color.blue - 1) < 0.0001)
        #expect(abs(color.alpha - 0.25) < 0.0001)
    }

    // A Display P3 red lies outside sRGB; it is moved to sRGB's edge.
    @Test func clampsWideGamutColors() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let red = try #require(CGColor(colorSpace: p3, components: [1, 0, 0, 1]))
        let color = try #require(PointerColor(red))
        #expect(color.red == 1)
        #expect((0...1).contains(color.green))
        #expect((0...1).contains(color.blue))
    }

    @Test func storesComponentsAsJSON() throws {
        let data = try JSONEncoder().encode(PointerColor.white)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Double])
        #expect(object == ["red": 1, "green": 1, "blue": 1, "alpha": 1])
    }
}
