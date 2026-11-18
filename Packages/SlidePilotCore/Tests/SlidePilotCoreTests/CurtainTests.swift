import SlidePilotCore
import Testing

@Suite
struct CurtainTests {
    @Test func startsHidden() {
        let curtain = Curtain.none
        #expect(!curtain.isShown)
    }

    @Test func sameKeyShowsAndHides() {
        var curtain = Curtain.none
        curtain.toggle(.black)
        #expect(curtain == .black)
        #expect(curtain.isShown)
        curtain.toggle(.black)
        #expect(curtain == .none)

        curtain.toggle(.white)
        #expect(curtain == .white)
        curtain.toggle(.white)
        #expect(curtain == .none)
    }

    // Black and white are mutually exclusive: the other color replaces the shown one.
    @Test func otherColorReplacesShownCurtain() {
        var curtain = Curtain.black
        curtain.toggle(.white)
        #expect(curtain == .white)
        curtain.toggle(.black)
        #expect(curtain == .black)
    }

    @Test func setShowsAndHidesOneColor() {
        var curtain = Curtain.none
        curtain.set(.black, shown: true)
        #expect(curtain == .black)
        curtain.set(.black, shown: true)
        #expect(curtain == .black)
        curtain.set(.white, shown: true)
        #expect(curtain == .white)
        // Hiding the color that is not shown keeps the shown one.
        curtain.set(.black, shown: false)
        #expect(curtain == .white)
        curtain.set(.white, shown: false)
        #expect(curtain == .none)
    }

    @Test func toggleNoneHides() {
        var curtain = Curtain.white
        curtain.toggle(.none)
        #expect(curtain == .none)
        curtain.toggle(.none)
        #expect(curtain == .none)
    }
}
