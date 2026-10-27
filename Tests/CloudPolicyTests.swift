import Foundation
import Security

/// Проверяем реальные атрибуты своей одноразовой записи; существующие ключи не читаются.
@main struct CloudPolicyTests {
    static func main() throws {
        let config = CloudTranslationEngine.sessionConfiguration()
        let systemProxy = URLSessionConfiguration.ephemeral.connectionProxyDictionary as NSDictionary?
        let proxy = config.connectionProxyDictionary as NSDictionary?
        guard proxy == systemProxy, !config.httpShouldSetCookies, config.urlCache == nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let provider = "audit-test-" + UUID().uuidString
        let query = ProviderKeychain.query(provider)
        defer { SecItemDelete(query as CFDictionary) }
        var legacy = query
        legacy[kSecValueData as String] = Data("synthetic-original".utf8)
        legacy[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        try ProviderKeychain.save("synthetic-replacement", provider: provider)
        var attributesQuery = query
        attributesQuery[kSecReturnAttributes as String] = true
        attributesQuery[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributesQuery as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              attributes[kSecValueData as String] as? Data == Data("synthetic-replacement".utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Legacy macOS Keychain не реализует iOS accessibility classes. Не выдаём
        // успешный SecItemUpdate за доказательство WhenUnlockedThisDeviceOnly.
        let policy = attributes[kSecAttrAccessible as String] as? String
        if let policy, policy != kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String {
            throw CocoaError(.fileReadCorruptFile)
        }
        let report: [String: Any] = ["status": "passed",
            "tests": ["system proxy inherited", "own Keychain record updated"],
            "accessibility_class": policy == nil ? "not enforced by legacy macOS backend" : "verified"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }
}
