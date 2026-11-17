import SlidePilotCore
import Testing

@MainActor
@Suite
struct ExternalDisplayStatusTests {
    @Test func startsDisconnected() {
        #expect(!ExternalDisplayStatus().isConnected)
    }

    @Test func connectedWhileAnySceneIsConnected() {
        let status = ExternalDisplayStatus()
        status.connect("a")
        #expect(status.isConnected)
        status.disconnect("a")
        #expect(!status.isConnected)
    }

    @Test func reportsOnlyTheFirstConnection() {
        let status = ExternalDisplayStatus()
        #expect(status.connect("a"))
        #expect(!status.connect("b"))
        #expect(!status.connect("a"))
    }

    /// iPadOS 27 can connect the next window's scene before the previous one disconnects.
    @Test func overlappingScenesStayConnected() {
        let status = ExternalDisplayStatus()
        status.connect("a")
        status.connect("b")
        status.disconnect("a")
        #expect(status.isConnected)
        status.disconnect("b")
        #expect(!status.isConnected)
    }

    @Test func disconnectingAnUnknownSceneChangesNothing() {
        let status = ExternalDisplayStatus()
        status.disconnect("a")
        #expect(!status.isConnected)
        status.connect("b")
        status.disconnect("a")
        #expect(status.isConnected)
    }
}
