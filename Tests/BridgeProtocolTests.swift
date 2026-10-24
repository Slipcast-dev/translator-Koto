import Foundation
import Darwin

enum BridgeTestFailure: Error { case assertion(String) }

@main
struct BridgeProtocolTests {
    static func main() throws {
        var checks: [String] = []
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw BridgeTestFailure.assertion(name) }
            checks.append(name)
        }
        let message = BridgeEnvelope(type: .translate, payload: ["text":"Привет 👋\nWorld","target":"en"])
        let encoded = try BridgeFrameDecoder.encode(message)
        var decoder = BridgeFrameDecoder()
        var decoded: [BridgeEnvelope] = []
        for byte in encoded { decoded += try decoder.append(Data([byte])) }
        try check(decoded.count == 1 && decoded[0].payload == message.payload, "bytewise fragmentation and Unicode")
        try decoder.finish()
        checks.append("complete EOF accepted")
        var combined = BridgeFrameDecoder()
        try check(try combined.append(encoded + encoded).count == 2, "multiple frames in one read")
        func reject(_ bytes: Data, _ name: String, finish: Bool = false) throws {
            var decoder = BridgeFrameDecoder()
            do {
                _ = try decoder.append(bytes)
                if finish { try decoder.finish() }
                throw BridgeTestFailure.assertion(name)
            } catch is BridgeProtocolFailure { checks.append(name) }
        }
        try reject(Data([0,0,0,0]), "zero length rejected")
        try reject(Data([1,0,16,0]), "oversize rejected before body")
        try reject(encoded.prefix(2), "short header EOF rejected", finish: true)
        try reject(encoded.dropLast(), "short body EOF rejected", finish: true)
        var overdeclared = encoded
        let length = encoded.count - 4 + 10
        for index in 0..<4 { overdeclared[index] = UInt8((length >> (8 * index)) & 255) }
        try reject(overdeclared, "valid JSON with overdeclared length rejected", finish: true)
        try reject(Data([1,0,0,0,255]), "invalid UTF8 rejected")
        try reject(Data([1,0,0,0,120]), "invalid JSON rejected")
        func raw(_ object: [String: Any]) throws -> Data {
            let body = try JSONSerialization.data(withJSONObject: object)
            var length = UInt32(body.count).littleEndian
            return withUnsafeBytes(of: &length) { Data($0) } + body
        }
        try reject(try raw(["v":2,"id":UUID().uuidString,"type":"ping","payload":[:]]), "wrong protocol version rejected")
        try reject(try raw(["v":1,"id":"not-an-id","type":"ping","payload":[:]]), "invalid request ID rejected")
        try reject(try raw(["v":1,"id":UUID().uuidString,"type":"ping","payload":["object":["nested":true]]]), "nonstring payload rejected")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("koto-test-" + UUID().uuidString)
        try PrivateStorage.ensureDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = directory.appendingPathComponent("token")
        try PrivateStorage.write(Data("first".utf8), to: secret)
        try check(try PrivateStorage.read(secret, maximum: 100) == Data("first".utf8), "private file round trip")
        let attrs = try FileManager.default.attributesOfItem(atPath: secret.path)
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private file permissions 0600")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        do {
            try PrivateStorage.write(Data("changed".utf8), to: link)
            throw BridgeTestFailure.assertion("symlink accepted")
        } catch is CocoaError { checks.append("symlink write rejected") }
        try check(try Data(contentsOf: secret) == Data("first".utf8), "symlink target not changed")
        try check(PrivateStorage.matches("secret","secret") && !PrivateStorage.matches("secret","secreu"),
                  "token equality checked")
        let report: [String: Any] = ["status":"passed","count":checks.count,"tests":checks]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
    }
}
