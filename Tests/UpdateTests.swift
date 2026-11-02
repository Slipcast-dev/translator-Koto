import Foundation

/// Проверка обновления на настоящих DMG, hdiutil, codesign и процессе-помощнике.
/// Сеть и GitHub не используются: транспорт подменён локальными файлами.
@main struct UpdateTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var passed: [String] = []
    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure(description: "FAILED: " + name) }
        passed.append(name)
    }

    static func shell(_ path: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "command failed: \(path) \(args)") }
    }

    static func buildNumber(of app: URL) -> Int? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return (info["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    static func releaseJSON(tag: String, dmg: String, size: Int64, host: String = "github.com", draft: Bool = false) -> String {
        """
        {"tag_name":"\(tag)","name":"Koto \(tag)","body":"## Что нового\\n- Исправления\\n- **Быстрее** запуск","draft":\(draft),
         "html_url":"https://github.com/Slipcast-dev/translator-Koto/releases/tag/\(tag)",
         "assets":[{"name":"\(dmg)","browser_download_url":"https://\(host)/x/\(dmg)","size":\(size)},
                   {"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/x/SHA256SUMS.txt","size":200}]}
        """
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { throw Failure(description: "usage: update-tests <Koto.app>") }
        let sourceApp = URL(fileURLWithPath: arguments[1])
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("koto-update-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 1. Версии и каталог релизов.
        let v14 = AppVersion.parse(tag: "v0.1.0-alpha.14")!
        try check(AppVersion.parse(tag: "v0.1.0-alpha.15")! > v14, "alpha.15 newer than alpha.14")
        try check(AppVersion.parse(tag: "v0.1.1-alpha.1")! > v14, "patch bump wins over build")
        try check(AppVersion.parse(tag: "v0.1.0", assetBuild: 1)! > v14, "stable release newer than alpha of same number")
        try check(AppVersion.parse(tag: "release-final") == nil, "garbage tag rejected")
        let name15 = "Koto-0.1.0-15-arm64-preview-ci.dmg"
        let feed = "[" + [
            releaseJSON(tag: "v0.1.0-alpha.14", dmg: "Koto-0.1.0-14-arm64-preview-ci.dmg", size: 1000),
            releaseJSON(tag: "v0.1.0-alpha.15", dmg: name15, size: 1000),
            releaseJSON(tag: "v0.1.0-alpha.16", dmg: "Koto-0.1.0-16-arm64-preview-ci.dmg", size: 1000, draft: true),
            releaseJSON(tag: "v0.1.0-alpha.17", dmg: "Koto-0.1.0-17-arm64-preview-ci.dmg", size: 1000, host: "evil.example.com"),
            releaseJSON(tag: "v0.1.0-alpha.18", dmg: "Koto-0.1.0-18-arm64-preview-ci.dmg", size: 900_000_000),
        ].joined(separator: ",") + "]"
        let picked = try UpdateCatalog.newest(from: Data(feed.utf8), newerThan: v14)
        try check(picked?.tag == "v0.1.0-alpha.15", "newest trusted non-draft release selected")
        try check(picked?.notes.contains("#") == false && picked?.notes.contains("**") == false, "markdown stripped from notes")
        try check(try UpdateCatalog.newest(from: Data(feed.utf8), newerThan: AppVersion.parse(tag: "v0.1.0-alpha.15")!) == nil, "no update when current")
        do { _ = try UpdateCatalog.newest(from: Data("not json".utf8), newerThan: v14); throw Failure(description: "bad json accepted") }
        catch is UpdateFailure { passed.append("bad json rejected") }
        try check(UpdateCatalog.expectedHash(in: String(repeating: "a", count: 64) + "  file.dmg\n", fileName: "file.dmg") != nil, "checksum line parsed")
        try check(UpdateCatalog.expectedHash(in: "zz  file.dmg", fileName: "file.dmg") == nil, "malformed checksum rejected")

        // 2. Зависшая утилита завершается по тайм-ауту.
        let began = ContinuousClock.now
        do { _ = try await UpdateProcess.run("/bin/sleep", ["30"], timeout: 1); throw Failure(description: "sleep not stopped") }
        catch UpdateFailure.timedOut { passed.append("hung helper stopped by timeout") }
        try check(began.duration(to: .now) < .seconds(10), "timeout returns promptly")

        // 3. Реальные DMG: старое приложение build N, новое N+1.
        let oldBuild = buildNumber(of: sourceApp) ?? 0
        let newBuild = oldBuild + 1
        let apps = root.appendingPathComponent("Apps"); try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let target = apps.appendingPathComponent("Koto.app")
        try shell("/usr/bin/ditto", [sourceApp.path, target.path])
        func makeDMG(build: Int, name: String) throws -> URL {
            let folder = root.appendingPathComponent("dmg-\(build)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let app = folder.appendingPathComponent("Koto.app")
            try shell("/usr/bin/ditto", [sourceApp.path, app.path])
            try shell("/usr/libexec/PlistBuddy", ["-c", "Set :CFBundleVersion \(build)", app.appendingPathComponent("Contents/Info.plist").path])
            try shell("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            let dmg = root.appendingPathComponent(name)
            try shell("/usr/bin/hdiutil", ["create", "-ov", "-format", "UDZO", "-fs", "HFS+", "-volname", "Koto", "-srcfolder", folder.path, dmg.path])
            return dmg
        }
        func sha(_ url: URL) throws -> String {
            let pipe = Process(); pipe.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            pipe.arguments = ["-a", "256", url.path]
            let out = Pipe(); pipe.standardOutput = out; try pipe.run(); pipe.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
        }
        let dmgNew = try makeDMG(build: newBuild, name: "Koto-0.1.0-\(newBuild)-arm64-preview-ci.dmg")
        let dmgSame = try makeDMG(build: oldBuild, name: "Koto-0.1.0-\(oldBuild)-arm64-preview-ci.dmg")
        let sizeNew = (try FileManager.default.attributesOfItem(atPath: dmgNew.path)[.size] as? NSNumber)?.int64Value ?? 0
        let goodSums = try sha(dmgNew) + "  " + dmgNew.lastPathComponent + "\n"
        let badSums = String(repeating: "0", count: 64) + "  " + dmgNew.lastPathComponent + "\n"
        let releases = "[" + releaseJSON(tag: "v0.1.0-alpha.\(newBuild)", dmg: dmgNew.lastPathComponent, size: sizeNew) + "]"

        func transport(sums: String, dmg: URL, slow: Bool = false) -> UpdateTransport {
            UpdateTransport(
                fetch: { url in
                    if url == UpdateTransport.releasesURL { return Data(releases.utf8) }
                    return Data(sums.utf8)
                },
                download: { _, destination, progress in
                    if slow { try await Task.sleep(for: .seconds(60)) }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: dmg, to: destination)
                    progress(sizeNew)
                })
        }
        let current = AppVersion.bundle(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any] ?? [:])!
        let work = root.appendingPathComponent("work")
        let bundleID = "dev.slipcast.koto"

        @MainActor func waitFor(_ model: UpdateModel, seconds: Double, _ done: (UpdateModel.Phase) -> Bool) async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            while ContinuousClock.now < deadline {
                if done(model.phase) { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        // 3a. Проверка находит обновление.
        var terminated = false
        let finder = UpdateModel(transport: transport(sums: goodSums, dmg: dmgNew), current: current, target: target,
                                       workDirectory: work, bundleIdentifier: bundleID, relaunch: false, terminate: { terminated = true })
        finder.check()
        let found = await waitFor(finder, seconds: 10) { if case .available = $0 { true } else { false } }
        try check(found, "check finds the newer release")
        guard case .available(let release) = finder.phase else { throw Failure(description: "no release") }

        // 3b. Неверная контрольная сумма: ничего не устанавливается.
        let tampered = UpdateModel(transport: transport(sums: badSums, dmg: dmgNew), current: current, target: target,
                                         workDirectory: work, bundleIdentifier: bundleID, relaunch: false, terminate: { terminated = true })
        tampered.install(release)
        let rejected = await waitFor(tampered, seconds: 60) { if case .failed = $0 { true } else { false } }
        try check(rejected && !terminated && buildNumber(of: target) == oldBuild, "checksum mismatch rejected and app untouched")

        // 3c. Пакет той же версии не ставится.
        let sameRelease = AppRelease(tag: release.tag, version: release.version, title: release.title, notes: "", page: release.page,
            dmg: ReleaseAsset(name: dmgSame.lastPathComponent, url: release.dmg.url,
                              size: (try FileManager.default.attributesOfItem(atPath: dmgSame.path)[.size] as? NSNumber)?.int64Value ?? 0),
            checksums: release.checksums)
        let sameSums = try sha(dmgSame) + "  " + dmgSame.lastPathComponent + "\n"
        let same = UpdateModel(transport: transport(sums: sameSums, dmg: dmgSame), current: current, target: target,
                                     workDirectory: work, bundleIdentifier: bundleID, relaunch: false, terminate: { terminated = true })
        same.install(sameRelease)
        let notNewer = await waitFor(same, seconds: 90) { if case .failed = $0 { true } else { false } }
        try check(notNewer && !terminated && buildNumber(of: target) == oldBuild, "same-version package rejected")

        // 3d. Отмена загрузки не зависает.
        let slow = UpdateModel(transport: transport(sums: goodSums, dmg: dmgNew, slow: true), current: current, target: target,
                                     workDirectory: work, bundleIdentifier: bundleID, relaunch: false, terminate: { terminated = true })
        slow.install(release)
        _ = await waitFor(slow, seconds: 5) { $0 == .downloading }
        let cancelStarted = ContinuousClock.now
        slow.cancel()
        try check(slow.phase == .idle && cancelStarted.duration(to: .now) < .seconds(1), "cancel during download is immediate")

        // 3e. Полная установка: помощник ждёт выхода «приложения» и заменяет bundle.
        let sleeper = Process(); sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep"); sleeper.arguments = ["3"]
        try sleeper.run()
        let installer = UpdateModel(transport: transport(sums: goodSums, dmg: dmgNew), current: current, target: target,
                                          workDirectory: work, bundleIdentifier: bundleID, relaunch: false,
                                          processID: sleeper.processIdentifier, terminate: { terminated = true })
        installer.install(release)
        let staged = await waitFor(installer, seconds: 120) { _ in terminated }
        try check(staged, "update downloaded, verified and handed to the installer")
        try check(buildNumber(of: target) == oldBuild, "bundle is not replaced while the app is still running")
        sleeper.waitUntilExit()
        var replaced = false
        for _ in 0..<150 where !replaced {
            replaced = buildNumber(of: target) == newBuild
            if !replaced { try await Task.sleep(for: .milliseconds(200)) }
        }
        try check(replaced, "bundle replaced after the app exits")
        try await Task.sleep(for: .seconds(1))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: apps.path))?.filter { $0 != "Koto.app" } ?? ["?"]
        try check(leftovers.isEmpty, "no staged or backup bundles left behind")
        try shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
        try check(true, "replaced app passes codesign verification")

        print(String(decoding: try JSONSerialization.data(withJSONObject: ["status": "passed", "tests": passed], options: [.sortedKeys]), as: UTF8.self))
    }
}
