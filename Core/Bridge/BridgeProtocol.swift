import Foundation

enum BridgeProtocolFailure: Error { case length, truncated, json, version, identity }
enum BridgeMessageType: String, Codable, Sendable {
    case hello, helloAck, translate, translated, ping, pong, cancel, error
}
struct BridgeEnvelope: Codable, Sendable {
    let v: Int
    let id: String
    let type: BridgeMessageType
    var payload: [String: String]
    init(id: String = UUID().uuidString, type: BridgeMessageType, payload: [String: String] = [:]) {
        v = 1; self.id = id; self.type = type; self.payload = payload
    }
}

/// Один формат для stdio и AF_UNIX: точный UInt32 little endian + UTF-8 JSON.
struct BridgeFrameDecoder {
    static let maximum = 1_048_576
    private var buffer = Data()
    var hasPartialFrame: Bool { !buffer.isEmpty }

    mutating func append(_ data: Data) throws -> [BridgeEnvelope] {
        guard buffer.count + data.count <= Self.maximum * 2 else { throw BridgeProtocolFailure.length }
        buffer.append(data)
        var messages: [BridgeEnvelope] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= Self.maximum else { throw BridgeProtocolFailure.length }
            let full = Int(length) + 4
            guard buffer.count >= full else { break }
            // Data после removeFirst может иметь ненулевой startIndex.
            // Диапазон строится относительно текущего начала, иначе второй кадр вызывает trap.
            let body = buffer.subdata(in: (buffer.startIndex + 4)..<(buffer.startIndex + full))
            guard String(data: body, encoding: .utf8) != nil else { throw BridgeProtocolFailure.json }
            let value: BridgeEnvelope
            do { value = try JSONDecoder().decode(BridgeEnvelope.self, from: body) }
            catch { throw BridgeProtocolFailure.json }
            guard value.v == 1 else { throw BridgeProtocolFailure.version }
            guard UUID(uuidString: value.id) != nil else { throw BridgeProtocolFailure.identity }
            messages.append(value)
            buffer.removeFirst(full)
        }
        return messages
    }

    func finish() throws { if !buffer.isEmpty { throw BridgeProtocolFailure.truncated } }

    static func encode(_ value: BridgeEnvelope) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count > 0, body.count <= maximum else { throw BridgeProtocolFailure.length }
        var length = UInt32(body.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(body)
        return frame
    }
}
