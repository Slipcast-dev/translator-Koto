import Foundation
import NaturalLanguage
import Security

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Секрет принадлежит одному провайдеру; UI никогда не загружает существующий ключ в поле.
enum ProviderKeychain {
    static func query(_ provider: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.slipcast.koto.cloud", kSecAttrAccount as String: provider]
    }
    static func read(_ provider: String) throws -> String {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw TranslationFailure.engineIssue(String(localized: "Save the selected provider’s API key in Settings."))
        }
        return key
    }
    static func save(_ key: String, provider: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= 4096, !clean.contains("\n"), !clean.contains("\r") else {
            throw TranslationFailure.engineIssue(String(localized: "Check the API key format."))
        }
        let data = Data(clean.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(provider)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteNoPermission) }
    }
    static func remove(_ provider: String) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteNoPermission) }
    }
}

/// Запрещаем redirects: заголовок авторизации не должен попасть на другой сервер.
private final class CloudRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class CloudTranslationEngine: TranslationEngine {
    enum Provider: String { case google, yandex }
    private let provider: Provider
    private let session: URLSession
    private var operation: Task<TranslationResult, Error>?
    private var operationID: UUID?
    var displayName: String { provider == .google ? "Google Cloud" : "Yandex Cloud" }
    init(_ provider: Provider) {
        self.provider = provider
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 50
        session = URLSession(configuration: config, delegate: CloudRedirectGuard(), delegateQueue: nil)
    }
    func supportedLanguages() async throws -> [TranslationLanguage] {
        // Консервативный общий набор. Остальные пары не рекламируются без проверки каталога API.
        ["ar","de","en","es","fr","hi","id","it","ja","ko","nl","pl","pt","ru","tr","uk","vi","zh"]
            .map { TranslationLanguage(id: $0) }.sorted { $0.displayName < $1.displayName }
    }
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness {
        _ = try ProviderKeychain.read(provider.rawValue)
        return .installed(request)
    }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let key = try ProviderKeychain.read(provider.rawValue)
        if provider == .yandex, request.text.count > 10_000 {
            throw TranslationFailure.engineIssue(String(localized: "Yandex accepts up to \(AppLocalization.number(10_000)) characters per request."))
        }
        let task = Task { () throws -> TranslationResult in
            let endpoint = provider == .google ? "https://translation.googleapis.com/language/translate/v2"
                : "https://translate.api.cloud.yandex.net/translate/v2/translate"
            guard let url = URL(string: endpoint) else { throw TranslationFailure.failed }
            var http = URLRequest(url: url)
            http.httpMethod = "POST"
            http.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            var body: [String: Any]
            if provider == .google {
                http.setValue(key, forHTTPHeaderField: "X-goog-api-key")
                body = ["q": request.text, "target": request.target.id, "format": "text"]
                if let source = request.source { body["source"] = source.id }
            } else {
                // API-key сервисного аккаунта: folderId не передаётся, согласно REST reference.
                http.setValue("Api-Key " + key, forHTTPHeaderField: "Authorization")
                body = ["texts": [request.text], "targetLanguageCode": request.target.id, "format": "PLAIN_TEXT"]
                if let source = request.source { body["sourceLanguageCode"] = source.id }
            }
            http.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: http)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                // Ответ сервиса может содержать пользовательский текст: не показываем сырое тело.
                let message = [401: String(localized: "API key rejected."), 403: String(localized: "Check the key permissions and API access."),
                               429: String(localized: "Provider quota exhausted. Try again later.")][status]
                    ?? String(localized: "Cloud service unavailable (HTTP \(status)).")
                throw TranslationFailure.engineIssue(message)
            }
            guard data.count <= 1_048_576,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranslationFailure.failed }
            let container = provider == .google ? (object["data"] as? [String: Any] ?? [:]) : object
            guard let first = (container["translations"] as? [[String: Any]])?.first,
                  let text = first[provider == .google ? "translatedText" : "text"] as? String, !text.isEmpty else {
                throw TranslationFailure.failed
            }
            let detected = first[provider == .google ? "detectedSourceLanguage" : "detectedLanguageCode"] as? String
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(request.text)
            guard let source = request.source ?? (detected ?? recognizer.dominantLanguage?.rawValue).map({ TranslationLanguage(id: $0) }) else {
                throw TranslationFailure.unableToIdentify
            }
            return TranslationResult(requestID: request.id, text: text, source: source, target: request.target)
        }
        operation = task; operationID = request.id
        defer { if operationID == request.id { operation = nil; operationID = nil } }
        do { return try await task.value }
        catch is CancellationError { throw TranslationFailure.cancelled }
        catch let e as URLError where e.code == .cancelled { throw TranslationFailure.cancelled }
        catch let failure as TranslationFailure { throw failure }
        catch { throw TranslationFailure.engineIssue(String(localized: "Unable to connect to the cloud provider.")) }
    }
    func cancel() { operation?.cancel(); operation = nil; operationID = nil }
}
