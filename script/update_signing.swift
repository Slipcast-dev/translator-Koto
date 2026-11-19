// Подпись обновлений Ed25519. Приватный ключ хранится только у владельца (секрет CI), в приложении — публичный.
//   swift script/update_signing.swift generate            → печатает пару ключей (base64, 32 байта)
//   swift script/update_signing.swift sign <файл> <вывод> → читает приватный ключ из KOTO_UPDATE_SIGNING_KEY
//   swift script/update_signing.swift verify <файл> <подпись> <публичный ключ base64>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE=" + key.rawRepresentation.base64EncodedString())
    print("PUBLIC=" + key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    let rest = Array(arguments.dropFirst())
    guard rest.count == 2, let encoded = ProcessInfo.processInfo.environment["KOTO_UPDATE_SIGNING_KEY"],
          let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
          let data = FileManager.default.contents(atPath: rest[0]) else { fail("usage: sign <file> <out> (KOTO_UPDATE_SIGNING_KEY)") }
    let signature = try key.signature(for: data)
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: URL(fileURLWithPath: rest[1]))
case "verify":
    let rest = Array(arguments.dropFirst())
    guard rest.count == 3, let data = FileManager.default.contents(atPath: rest[0]),
          let signatureText = FileManager.default.contents(atPath: rest[1]),
          let signature = Data(base64Encoded: String(decoding: signatureText, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          let publicRaw = Data(base64Encoded: rest[2]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicRaw),
          key.isValidSignature(signature, for: data) else { fail("signature invalid") }
    print("ok")
default:
    fail("usage: generate | sign <file> <out> | verify <file> <sig> <public>")
}
