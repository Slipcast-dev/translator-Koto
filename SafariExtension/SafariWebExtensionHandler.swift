import AppKit
import SafariServices

/// Точка входа расширения Safari: принимает сообщение страницы и передаёт его мосту Koto.
/// Текст не пишется в журналы, ответ содержит только перевод или код ошибки.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = Self.reply(to: message)
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func reply(to message: [String: Any]?) -> [String: Any] {
        guard let message, message["action"] as? String == "translate",
              let text = message["text"] as? String, let target = message["target"] as? String,
              let origin = message["pageOrigin"] as? String,
              languageIdentifier(target) else { return ["ok": false, "error": "invalid_request"] }
        let source = message["source"] as? String ?? "auto"
        guard source == "auto" || languageIdentifier(source) else { return ["ok": false, "error": "invalid_language"] }
        do {
            let translated = try SafariBridgeClient.translate(
                text: text, source: source, target: target, pageOrigin: origin, launchApp: launchContainingApp)
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
