import Foundation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Очередь FIFO к единственному слоту модели. Таймаут HTTP-запроса начинается только после того,
/// как слот получен: ожидание соседних запросов больше не расходует время текущего.
@MainActor
final class InferenceGate {
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    var waiting: Int { waiters.count }

    func acquire() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        }, onCancel: {
            Task { @MainActor in self.abandon(id) }
        })
    }
    func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().continuation.resume() }
    }
    private func abandon(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Общая граница локального JSON inference для перевода и пояснений. Никаких внешних endpoint.
@MainActor
struct LocalGenerationService {
    let runtime: LocalRuntimeSupervisor
    func generate(instruction: String, input: String, schema: [String:Any], maximumTokens: Int = 1536) async throws -> Data {
        try await runtime.gate.acquire()
        defer { runtime.gate.release() }
        try Task.checkCancellation()
        let endpoint = try await runtime.start()
        try Task.checkCancellation()
        let body = try JSONSerialization.data(withJSONObject: Self.payload(instruction: instruction, input: input,
                                                                           schema: schema, maximumTokens: maximumTokens))
        let (data, status) = try await LocalRuntimeTransport.request(endpoint, path: "/v1/chat/completions", body: body)
        try Task.checkCancellation()
        guard status == 200, data.count <= 1_048_576,
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
