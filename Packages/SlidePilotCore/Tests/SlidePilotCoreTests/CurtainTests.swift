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

@Suite
struct CurtainStateTests {
    @Test func buttonStartsWithBlack() {
        var state = CurtainState()
        #expect(state.color == .black)
        #expect(state.toggled == .black)
        state.toggle()
        #expect(state.shown == .black)
        state.toggle()
        #expect(state.shown == .none)
    }

    // Once white was chosen, the button keeps showing white (CUR-01, changed 2026-11-25).
    @Test func buttonKeepsTheColorChosenLast() {
        var state = CurtainState()
        state.shown = .white
        state.toggle()
        #expect(state.shown == .none)
        #expect(state.color == .white)
        state.toggle()
        #expect(state.shown == .white)
        state.toggle()
        state.toggle()
        #expect(state.shown == .white)
    }

    @Test func choosingBlackAgainSwitchesBack() {
        var state = CurtainState(shown: .white)
        state.shown.toggle(.black)
        #expect(state.shown == .black)
        state.toggle()
        state.toggle()
        #expect(state.shown == .black)
    }

    // Hiding the curtain never changes the remembered color.
    @Test func hidingKeepsTheColor() {
        var state = CurtainState(shown: .white)
        state.shown = .none
        #expect(state.color == .white)
        state.shown.set(.black, shown: false)
        #expect(state.color == .white)
    }

    // The Mac's color menu picks the color without showing the curtain.
    @Test func choosingTheColorWhileHiddenOnlyRemembersIt() {
        var state = CurtainState()
        state.setColor(.white)
        #expect(state.shown == .none)
        #expect(state.color == .white)
        state.toggle()
        #expect(state.shown == .white)
    }

    @Test func choosingTheColorWhileShownSwitchesTheCurtain() {
        var state = CurtainState(shown: .black)
        state.setColor(.white)
        #expect(state.shown == .white)
        #expect(state.color == .white)
    }

    @Test func choosingNoColorChangesNothing() {
        var state = CurtainState(shown: .white)
        state.setColor(.none)
        #expect(state == CurtainState(shown: .white))
    }

    @Test func initFromShownCurtain() {
        #expect(CurtainState(shown: .white).color == .white)
        #expect(CurtainState(shown: .none).color == .black)
        #expect(CurtainState(shown: .white).toggled == .none)
    }
}
