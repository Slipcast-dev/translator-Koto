import Foundation
import Security

/// Минимальный DER encoder для собственного X.509 сертификата. Приватный RSA-ключ
/// создаётся постоянным объектом Keychain и никогда не экспортируется на диск.
enum DER {
    static func value(_ tag: UInt8, _ content: Data) -> Data {
        var result = Data([tag])
        if content.count < 128 { result.append(UInt8(content.count)) }
        else {
            var count = content.count
            var bytes: [UInt8] = []
            while count > 0 { bytes.insert(UInt8(count & 255), at: 0); count >>= 8 }
            result.append(0x80 | UInt8(bytes.count)); result.append(contentsOf: bytes)
        }
        result.append(content); return result
    }
    static func seq(_ values: Data...) -> Data { value(0x30, values.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { value(0x06, Data(bytes)) }
    static func integer(_ bytes: Data) -> Data {
        var clean = bytes
        while clean.count > 1 && clean.first == 0 { clean.removeFirst() }
        if let first = clean.first, first & 0x80 != 0 { clean.insert(0, at: 0) }
        return value(0x02, clean)
    }
    static func bitString(_ bytes: Data) -> Data { value(0x03, Data([0]) + bytes) }
}

enum IdentityError: Error { case security(OSStatus), failed(String) }

@main struct CreateSigningIdentity {
    static func main() throws {
        let label = "Koto — Slipcast-Dev"
        guard CommandLine.arguments.count == 2 else { throw IdentityError.failed("public certificate output required") }
        var oldCertificate: CFTypeRef?
        let certificateQuery: [String:Any] = [kSecClass as String:kSecClassCertificate,
            kSecAttrLabel as String:label,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        let oldStatus = SecItemCopyMatching(certificateQuery as CFDictionary,&oldCertificate)
        if oldStatus == errSecSuccess, let data = oldCertificate as? Data {
            try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
            print("Existing public certificate retained: " + label)
            return
        }
        guard oldStatus == errSecItemNotFound else { throw IdentityError.security(oldStatus) }
        let tag = Data("dev.slipcast.koto.signing.v1".utf8)
        var existing: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecReturnRef as String: true]
        let found = SecItemCopyMatching(query as CFDictionary, &existing)
        let key: SecKey
        if found == errSecSuccess, let existing {
            key = existing as! SecKey
        } else {
            guard found == errSecItemNotFound else { throw IdentityError.security(found) }
            let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048,
                kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: tag, kSecAttrLabel as String: label,
                    kSecAttrIsExtractable as String: false]]
            var error: Unmanaged<CFError>?
            guard let created = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
                throw IdentityError.failed("Keychain could not create the nonextractable key")
            }
            key = created
        }
        guard let publicKey = SecKeyCopyPublicKey(key) else { throw IdentityError.failed("public key missing") }
        var error: Unmanaged<CFError>?
        guard let rsa = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IdentityError.failed("public key representation missing")
        }
        // rsaEncryption и sha256WithRSAEncryption OID из PKCS#1; NULL обязателен для совместимости.
        let rsaAlgorithm = DER.seq(DER.oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01]), DER.value(0x05,Data()))
        let signatureAlgorithm = DER.seq(DER.oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b]), DER.value(0x05,Data()))
        let name = DER.seq(DER.value(0x31, DER.seq(DER.oid([0x55,0x04,0x03]), DER.value(0x0c,Data(label.utf8)))))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let now = Date()
        let validity = DER.seq(DER.value(0x17,Data(formatter.string(from:now.addingTimeInterval(-300)).utf8)),
            DER.value(0x17,Data(formatter.string(from:now.addingTimeInterval(5*365*86400)).utf8)))
        var serial = [UInt8](repeating:0,count:16)
        guard SecRandomCopyBytes(kSecRandomDefault,serial.count,&serial) == errSecSuccess else { throw IdentityError.failed("random failed") }
        let critical = DER.value(0x01,Data([0xff]))
        // BasicConstraints CA=false; KeyUsage digitalSignature; EKU codeSigning, без широких назначений.
        let constraints = DER.seq(DER.oid([0x55,0x1d,0x13]),critical,DER.value(0x04,DER.seq()))
        let usage = DER.seq(DER.oid([0x55,0x1d,0x0f]),critical,DER.value(0x04,DER.value(0x03,Data([7,0x80]))))
        let eku = DER.seq(DER.oid([0x55,0x1d,0x25]),DER.value(0x04,DER.seq(DER.oid([0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x03]))))
        let tbs = DER.seq(DER.value(0xa0,DER.integer(Data([2]))),DER.integer(Data(serial)),signatureAlgorithm,name,validity,name,
            DER.seq(rsaAlgorithm,DER.bitString(rsa)),DER.value(0xa3,DER.seq(constraints,usage,eku)))
        guard let signature = SecKeyCreateSignature(key,.rsaSignatureMessagePKCS1v15SHA256,tbs as CFData,&error) as Data? else {
            throw IdentityError.failed("Keychain refused signing")
        }
        let certificateData = DER.seq(tbs,signatureAlgorithm,DER.bitString(signature))
        guard let certificate = SecCertificateCreateWithData(nil,certificateData as CFData) else { throw IdentityError.failed("invalid DER certificate") }
        let status = SecItemAdd([kSecClass as String:kSecClassCertificate,kSecValueRef as String:certificate,
            kSecAttrLabel as String:label] as CFDictionary,nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityError.security(status) }
        // Выводится только публичный сертификат. Trust Settings и Gatekeeper не меняются.
        guard CommandLine.arguments.count == 2 else { throw IdentityError.failed("public certificate output required") }
        try certificateData.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
        print("Created self-signed code-signing certificate: " + label)
    }
}
