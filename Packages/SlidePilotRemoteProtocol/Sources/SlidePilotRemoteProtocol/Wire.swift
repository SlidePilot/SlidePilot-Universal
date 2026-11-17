import Foundation

/// A message that one role sends to the other after the handshake.
public protocol RemoteWireMessage: Sendable {
    /// The role that sends this message type.
    static var sender: RemoteRole { get }
    /// JSON with a `type` discriminator and an optional `payload`.
    func wireData() throws(RemoteProtocolError) -> Data
    /// `nil` for an unknown `type`, so newer peers can add messages without breaking older ones.
    static func fromWire(_ data: Data) throws(RemoteProtocolError) -> Self?
}

/// JSON envelope `{"type": …, "payload": …}` shared by all message enums.
enum Wire {
    private struct TypeOnly: Decodable {
        let type: String
    }

    private struct Envelope<Payload: Encodable>: Encodable {
        let type: String
        let payload: Payload
    }

    private struct PayloadOnly<Payload: Decodable>: Decodable {
        let payload: Payload
    }

    static func encode(type: String) throws(RemoteProtocolError) -> Data {
        do {
            return try JSONEncoder().encode(["type": type])
        } catch {
            throw .invalidMessage
        }
    }

    static func encode<Payload: Encodable>(type: String, payload: Payload) throws(RemoteProtocolError) -> Data {
        do {
            return try JSONEncoder().encode(Envelope(type: type, payload: payload))
        } catch {
            throw .invalidMessage
        }
    }

    static func type(of data: Data) throws(RemoteProtocolError) -> String {
        do {
            return try JSONDecoder().decode(TypeOnly.self, from: data).type
        } catch {
            throw .invalidMessage
        }
    }

    static func payload<Payload: Decodable>(_: Payload.Type, from data: Data) throws(RemoteProtocolError) -> Payload {
        do {
            return try JSONDecoder().decode(PayloadOnly<Payload>.self, from: data).payload
        } catch {
            throw .invalidMessage
        }
    }
}
