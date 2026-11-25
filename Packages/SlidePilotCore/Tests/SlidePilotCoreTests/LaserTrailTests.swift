import CoreGraphics
import SlidePilotCore
import Testing

@Suite
struct LaserTrailTests {
    private let a = RelativePoint(x: 0.1, y: 0.2)
    private let b = RelativePoint(x: 0.3, y: 0.4)
    private let c = RelativePoint(x: 0.5, y: 0.6)

    @Test func startsEmptyAndInvisible() {
        let trail = LaserTrail()
        #expect(trail.isEmpty)
        #expect(!trail.isDrawing)
        #expect(trail.opacity(at: 0, reduceMotion: false) == 0)
        #expect(trail.removalTime == nil)
    }

    @Test func drawsAStroke() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.extend(to: b)
        trail.extend(to: b)
        #expect(trail.isDrawing)
        #expect(trail.strokes == [[a, b]])
        #expect(trail.liftTime == nil)
    }

    @Test func extendingWithoutAStrokeDoesNothing() {
        var trail = LaserTrail()
        trail.extend(to: a)
        #expect(trail.isEmpty)
    }

    // Strokes stay fully visible while drawing, however long it takes.
    @Test func staysWhileDrawing() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        #expect(trail.opacity(at: 1000, reduceMotion: false) == 1)
        #expect(trail.opacity(at: 1000, reduceMotion: true) == 1)
    }

    // Like Keynote: hold for 1.5 s after the lift, then fade out over 0.5 s.
    @Test func fadesAfterTheLastLift() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.end(time: 11)
        #expect(trail.fadeStart == 12.5)
        #expect(trail.removalTime == 13)
        #expect(trail.opacity(at: 11, reduceMotion: false) == 1)
        #expect(trail.opacity(at: 12.4, reduceMotion: false) == 1)
        #expect(trail.opacity(at: 12.75, reduceMotion: false) == 0.5)
        #expect(trail.opacity(at: 13, reduceMotion: false) == 0)
        #expect(trail.opacity(at: 20, reduceMotion: false) == 0)
    }

    // Reduce Motion: no fade animation, the strokes still disappear.
    @Test func vanishesWithoutFadeWithReduceMotion() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.end(time: 11)
        #expect(trail.opacity(at: 12.4, reduceMotion: true) == 1)
        #expect(trail.opacity(at: 12.5, reduceMotion: true) == 0)
        #expect(trail.opacity(at: 12.75, reduceMotion: true) == 0)
    }

    // All strokes of one gesture stay together and fade together.
    @Test func strokesInQuickSuccessionFormOneGesture() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.end(time: 11)
        trail.begin(at: b, time: 12)
        #expect(trail.strokes == [[a], [b]])
        #expect(trail.opacity(at: 12.6, reduceMotion: false) == 1)
        trail.extend(to: c)
        trail.end(time: 14)
        #expect(trail.strokes == [[a], [b, c]])
        #expect(trail.opacity(at: 15.4, reduceMotion: false) == 1)
        #expect(trail.removalTime == 16)
    }

    // A stroke that starts once the previous gesture fades begins a new gesture.
    @Test func aLaterStrokeStartsANewGesture() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.end(time: 11)
        trail.begin(at: b, time: 12.5)
        #expect(trail.strokes == [[b]])
        #expect(trail.opacity(at: 12.5, reduceMotion: false) == 1)
    }

    @Test func removesExpiredStrokesOnlyWhenGone() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.removeExpired(at: 100)
        #expect(!trail.isEmpty, "never while drawing")
        trail.end(time: 11)
        trail.removeExpired(at: 12.9)
        #expect(!trail.isEmpty)
        trail.removeExpired(at: 13)
        #expect(trail.isEmpty)
        #expect(trail.liftTime == nil)
    }

    @Test func endOnlyEndsADrawnStroke() {
        var trail = LaserTrail()
        trail.end(time: 5)
        #expect(trail.liftTime == nil)
        trail.begin(at: a, time: 10)
        trail.end(time: 11)
        trail.end(time: 20)
        #expect(trail.liftTime == 11)
    }

    @Test func clearRemovesEverything() {
        var trail = LaserTrail()
        trail.begin(at: a, time: 10)
        trail.clear()
        #expect(trail.isEmpty)
        #expect(!trail.isDrawing)
        trail.extend(to: b)
        #expect(trail.isEmpty)
    }
}

@Suite @MainActor
struct PointerLaserTests {
    private let slide = CGSize(width: 400, height: 200)

    private func laserPointer() -> PointerState {
        PointerState(isShown: true, appearance: .laser)
    }

    @Test func drawsOnlyWhileTheLaserIsShown() {
        let hidden = PointerState(isShown: false, appearance: .laser)
        hidden.laserMoved(to: CGPoint(x: 100, y: 50), inSlideOfSize: slide, time: 1)
        #expect(hidden.laser.isEmpty)

        let otherAppearance = PointerState(isShown: true, appearance: .dot)
        otherAppearance.laserMoved(to: CGPoint(x: 100, y: 50), inSlideOfSize: slide, time: 1)
        #expect(otherAppearance.laser.isEmpty)
        #expect(!otherAppearance.isLaserActive)
    }

    @Test func pointsAreRelativeToTheSlide() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 100, y: 50), inSlideOfSize: slide, time: 1)
        pointer.laserMoved(to: CGPoint(x: 400, y: 200), inSlideOfSize: slide, time: 1.1)
        // Beyond the edge the stroke goes on; the layer clips it to the slide.
        pointer.laserMoved(to: CGPoint(x: 440, y: 200), inSlideOfSize: slide, time: 1.2)
        #expect(pointer.laser.strokes == [[
            RelativePoint(x: 0.25, y: 0.25), RelativePoint(x: 1, y: 1), RelativePoint(x: 1.1, y: 1),
        ]])
    }

    @Test func ignoresAnEmptySlide() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 1, y: 1), inSlideOfSize: .zero, time: 1)
        #expect(pointer.laser.isEmpty)
    }

    @Test func eachDragIsOneStroke() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide, time: 1)
        pointer.laserEnded(time: 1.5)
        pointer.laserMoved(to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 2)
        pointer.laserEnded(time: 2.5)
        #expect(pointer.laser.strokes.count == 2)
        #expect(pointer.laser.liftTime == 2.5)
    }

    @Test func removesFadedStrokes() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide, time: 1)
        pointer.laserEnded(time: 2)
        pointer.removeExpiredLaser(at: 3)
        #expect(!pointer.laser.isEmpty)
        pointer.removeExpiredLaser(at: 4)
        #expect(pointer.laser.isEmpty)
    }

    // Hiding the pointer or choosing another appearance removes the strokes at once.
    @Test func hidingOrSwitchingClearsTheStrokes() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide, time: 1)
        pointer.isShown = false
        #expect(pointer.laser.isEmpty)

        pointer.isShown = true
        pointer.laserMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide, time: 1)
        pointer.appearance = .dot
        #expect(pointer.laser.isEmpty)
    }

    @Test func aDragStartsAtItsStartLocation() {
        let pointer = laserPointer()
        pointer.laserDragged(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 1)
        pointer.laserDragged(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 200), inSlideOfSize: slide, time: 1.1)
        #expect(pointer.laser.strokes == [[
            RelativePoint(x: 0, y: 0), RelativePoint(x: 0.5, y: 0.5), RelativePoint(x: 1, y: 1),
        ]])
    }

    // A slide change mid-drag must not draw a line from the drag's start on the new slide.
    @Test func aSlideChangeEndsTheDragInProgress() {
        let pointer = laserPointer()
        pointer.laserDragged(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50), inSlideOfSize: slide, time: 1)
        pointer.clearLaser()
        #expect(pointer.laser.isEmpty)
        #expect(!pointer.laser.isDrawing)
        pointer.laserDragged(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 1.1)
        #expect(pointer.laser.isEmpty)
        // The next drag draws again.
        pointer.laserEnded(time: 1.2)
        pointer.laserDragged(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 2)
        #expect(pointer.laser.strokes == [[RelativePoint(x: 0.5, y: 0.5)]])
    }

    // Clearing without a drag in progress does not block the next drag.
    @Test func aSlideChangeWithoutADragBlocksNothing() {
        let pointer = laserPointer()
        pointer.clearLaser()
        pointer.laserMoved(to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 1)
        #expect(!pointer.laser.isEmpty)
    }

    // Hiding the pointer mid-drag turns the gesture off, which may never report its end;
    // the laser must still draw once it is back.
    @Test func hidingMidDragDoesNotBlockTheLaser() {
        let pointer = laserPointer()
        pointer.laserMoved(to: CGPoint(x: 0, y: 0), inSlideOfSize: slide, time: 1)
        pointer.isShown = false
        pointer.isShown = true
        pointer.laserMoved(to: CGPoint(x: 200, y: 100), inSlideOfSize: slide, time: 2)
        #expect(pointer.laser.strokes == [[RelativePoint(x: 0.5, y: 0.5)]])
    }
}
