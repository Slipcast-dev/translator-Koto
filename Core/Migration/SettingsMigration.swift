import Foundation

/// Явный обмен только разрешёнными настройками; неизвестный plist Lingo и секреты не мигрируются.
struct SettingsMigration: Codable {
    let schema: Int
    let appearance: String
    let source: String
    let target: String
    static func parse(_ data: Data) throws -> Self {
        guard data.count <= 65_536,
              let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(object.keys) == Set(["schema","appearance","source","target"]) else { throw CocoaError(.fileReadCorruptFile) }
        let result = try JSONDecoder().decode(Self.self,from:data)
        let validLanguage: (String) -> Bool = { value in
            value.count <= 32 && value.range(of:"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$",options:.regularExpression) != nil
        }
        guard result.schema == 1, ["system","light","dark"].contains(result.appearance),
              (result.source == "auto" || validLanguage(result.source)), validLanguage(result.target) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }
}
