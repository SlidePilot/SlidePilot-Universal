import Foundation
import Testing
@testable import SlidePilotRemoteProtocol

struct FramingTests {
    @Test func framePrefixesBigEndianLength() throws {
        let framed = try FrameEncoder.frame(Data([0xAA, 0xBB, 0xCC]))
        #expect(framed == Data([0, 0, 0, 3, 0xAA, 0xBB, 0xCC]))
    }

    @Test func decoderJoinsFramesSplitAcrossChunks() throws {
        let framed = try FrameEncoder.frame(Data("hello".utf8)) + FrameEncoder.frame(Data("world".utf8))
        var decoder = FrameDecoder()
        var frames: [Data] = []
        // Feed one byte at a time, as TCP may deliver.
        for byte in framed {
            decoder.append(Data([byte]))
            while let frame = try decoder.nextFrame() { frames.append(frame) }
        }
        #expect(frames == [Data("hello".utf8), Data("world".utf8)])
    }

    @Test func decoderReturnsSeveralFramesFromOneChunk() throws {
        var decoder = FrameDecoder()
        decoder.append(try FrameEncoder.frame(Data([1])) + FrameEncoder.frame(Data()) + FrameEncoder.frame(Data([2, 3])))
        #expect(try decoder.nextFrame() == Data([1]))
        #expect(try decoder.nextFrame() == Data())
        #expect(try decoder.nextFrame() == Data([2, 3]))
        #expect(try decoder.nextFrame() == nil)
    }

    @Test func decoderRejectsOversizedFrameBeforeBuffering() {
        var decoder = FrameDecoder()
        decoder.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        #expect(throws: RemoteProtocolError.frameTooLarge(Int(UInt32.max))) {
            try decoder.nextFrame()
        }
    }

    @Test func encoderRejectsOversizedPayload() {
        let payload = Data(count: FrameDecoder.maximumFrameLength + 1)
        #expect(throws: RemoteProtocolError.frameTooLarge(payload.count)) {
            try FrameEncoder.frame(payload)
        }
    }
}
