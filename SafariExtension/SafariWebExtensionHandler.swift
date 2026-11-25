import AppKit
import SafariServices

/// Поколение отмены: «Отмена» в popup останавливает все запросы, начатые раньше неё.
private final class CancellationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    var current: Int { lock.lock(); defer { lock.unlock() }; return generation }
    func cancelAll() { lock.lock(); generation += 1; lock.unlock() }
}

/// Контекст расширения передаётся в фоновую очередь и используется там ровно один раз.
private struct PendingReply: @unchecked Sendable {
    let context: NSExtensionContext
    let message: [String: String]
    func complete(_ reply: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}

/// Точка входа расширения Safari: принимает сообщение страницы и передаёт его мосту Koto.
/// Текст не пишется в журналы, ответ содержит только перевод или код ошибки.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let cancellations = CancellationRegistry()

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let raw = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let pending = PendingReply(context: context, message: raw.compactMapValues { $0 as? String })
        if pending.message["action"] == "cancel" {
            Self.cancellations.cancelAll()
            pending.complete(["ok": true])
            return
        }
        let generation = Self.cancellations.current
        DispatchQueue.global(qos: .userInitiated).async {
            pending.complete(Self.reply(to: pending.message) { Self.cancellations.current != generation })
        }
    }

    private static func reply(to message: [String: String], isCancelled: () -> Bool) -> [String: Any] {
        guard message["action"] == "translate",
              let text = message["text"], let target = message["target"],
              let origin = message["pageOrigin"],
              languageIdentifier(target) else { return ["ok": false, "error": "invalid_request"] }
        let source = message["source"] ?? "auto"
        guard source == "auto" || languageIdentifier(source) else { return ["ok": false, "error": "invalid_language"] }
        do {
            let translated = try SafariBridgeClient.translate(
                text: text, source: source, target: target, pageOrigin: origin,
                launchApp: launchContainingApp, isCancelled: isCancelled)
            return ["ok": true, "text": translated]
        } catch let failure as SafariBridgeClient.Failure {
            return ["ok": false, "error": failure.code]
        } catch {
            return ["ok": false, "error": "bridge_error"]
        }
    }

    private static func languageIdentifier(_ value: String) -> Bool {
        value.count <= 32 && value.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil
    }

    /// Koto.app/Contents/PlugIns/Koto Safari.appex → Koto.app. Запуск в фоне, без перехвата фокуса Safari.
    private static func launchContainingApp() {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: nil)
    }
}
