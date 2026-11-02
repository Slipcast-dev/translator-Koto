/// Публичный origin закреплён manifest key; это не секрет или токен.
enum BridgeOrigin {
    static let allowed = "chrome-extension://bodbmpckhpjhkkhhadamlbkddaikilok/"
    /// Расширение Safari — отдельный клиент с собственным идентификатором; Chrome host по-прежнему принимает только allowed.
    static let safari = "safari-web-extension://dev.slipcast.koto.safari/"
    static func accepts(_ origin: String?) -> Bool { origin == allowed || origin == safari }
}
