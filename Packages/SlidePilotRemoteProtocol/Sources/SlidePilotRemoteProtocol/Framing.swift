import Foundation

/// Frames: a 4-byte big-endian length, then the payload (ADR 0017).
public enum FrameEncoder {
    public static func frame(_ payload: Data) throws(RemoteProtocolError) -> Data {
        guard payload.count <= FrameDecoder.maximumFrameLength else {
            throw .frameTooLarge(payload.count)
        }
        let length = UInt32(payload.count)
        var data = Data(capacity: 4 + payload.count)
        data.append(contentsOf: [
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        data.append(payload)
        return data
    }
}

/// Splits a byte stream into frames. TCP delivers arbitrary chunks, so frames may arrive
/// split or several at once.
public struct FrameDecoder: Sendable {
    /// Large enough for a full-resolution slide image, small enough to bound memory.
    public static let maximumFrameLength = 16 * 1024 * 1024

    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) {
        buffer.append(bytes)
    }

    /// The next complete frame's payload, or `nil` if more bytes are needed.
    public mutating func nextFrame() throws(RemoteProtocolError) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let start = buffer.startIndex
        let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
        guard length <= Self.maximumFrameLength else { throw .frameTooLarge(length) }
        guard buffer.count >= 4 + length else { return nil }
        let payload = Data(buffer[start + 4..<start + 4 + length])
        buffer.removeSubrange(start..<start + 4 + length)
        return payload
    }
}
