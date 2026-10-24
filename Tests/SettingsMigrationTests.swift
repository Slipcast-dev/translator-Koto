import Foundation
@main struct SettingsMigrationTests {
    static func main() throws {
        let valid = Data(#"{"schema":1,"appearance":"dark","source":"auto","target":"ru"}"#.utf8)
        let parsed = try SettingsMigration.parse(valid)
        guard parsed.appearance == "dark",parsed.target == "ru" else { exit(1) }
        var rejected = 0
        for source in [
            #"{"schema":2,"appearance":"dark","source":"auto","target":"ru"}"#,
            #"{"schema":1,"appearance":"evil","source":"auto","target":"ru"}"#,
            #"{"schema":1,"appearance":"dark","source":"auto","target":"../../ru"}"#,
            #"{"schema":1,"appearance":"dark","source":"auto","target":"ru","apiKey":"fixture-not-a-secret"}"#,
            #"{"schema":1,"appearance":"dark","source":"auto"}"#,
            String(repeating:"x",count:65_537)
        ] {
            do { _ = try SettingsMigration.parse(Data(source.utf8)); exit(1) }
            catch { rejected += 1 }
        }
        print("{\"status\":\"passed\",\"valid_imports\":1,\"invalid_imports_rejected\":\(rejected)}")
    }
}
