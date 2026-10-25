import Foundation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Общая граница локального JSON inference для перевода и пояснений. Никаких внешних endpoint.
@MainActor
struct LocalGenerationService {
    let runtime: LocalRuntimeSupervisor
    func generate(instruction: String, input: String, schema: [String:Any], maximumTokens: Int = 1536) async throws -> Data {
        try Task.checkCancellation()
        let endpoint = try await runtime.start()
        try Task.checkCancellation()
        var http = URLRequest(url:endpoint.baseURL.appendingPathComponent("v1/chat/completions"))
        http.httpMethod = "POST"; http.timeoutInterval = 120
        http.setValue("application/json",forHTTPHeaderField:"Content-Type")
        http.setValue("Bearer " + endpoint.token,forHTTPHeaderField:"Authorization")
        http.httpBody = try JSONSerialization.data(withJSONObject:Self.payload(instruction:instruction,input:input,schema:schema,maximumTokens:maximumTokens))
        let (data,response) = try await runtime.session.data(for:http)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576,
              let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let first = (object["choices"] as? [[String:Any]])?.first,
              first["finish_reason"] as? String == "stop",
              let message = first["message"] as? [String:Any], let content = message["content"] as? String,
              let answer = content.data(using:.utf8), !answer.isEmpty else {
            // Length и HTTP context overflow не выдаются за полноценный перевод.
            throw TranslationFailure.engineIssue(String(localized: "The local model did not return a complete response. Try a smaller section."))
        }
        return answer
    }
    static func payload(instruction: String, input: String, schema: [String:Any], maximumTokens: Int) -> [String:Any] {
        // Прямая проверка контракта защищает от повторного ослабления JSON grammar.
        return ["model":"local",
            "messages":[["role":"system","content":instruction],["role":"user","content":input]],
            "chat_template_kwargs":["enable_thinking":false],"temperature":0.0,"max_tokens":maximumTokens,"stream":false,
            // Закреплённый server-common.cpp читает вложенный json_schema.schema.
            // README этой версии допускает устаревший плоский пример, который ослаблял grammar.
            "response_format":["type":"json_schema","json_schema":["name":"koto_response","strict":true,"schema":schema]]]
    }

}
