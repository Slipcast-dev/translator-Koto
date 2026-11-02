import CryptoKit
import Foundation

// Логика обновления без AppKit/SwiftUI: её можно проверить отдельным harness на настоящих DMG и процессах.

/// Порядок версий: числа, затем стабильный выпуск старше alpha, затем build.
nonisolated struct AppVersion: Comparable, Sendable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let stable: Bool
    let build: Int

    var display: String { "\(major).\(minor).\(patch)" + (stable ? "" : "-alpha") + " (\(build))" }

    private var key: [Int] { [major, minor, patch, stable ? 1 : 0, build] }
    static func < (left: Self, right: Self) -> Bool { left.key.lexicographicallyPrecedes(right.key) }

    /// Тег вида v0.1.0-alpha.14 или v0.2.0; build стабильного выпуска берётся из имени DMG.
    nonisolated static func parse(tag: String, assetBuild: Int? = nil) -> AppVersion? {
        let pattern = #"^v?(\d+)\.(\d+)\.(\d+)(?:-([A-Za-z]+)\.?(\d+))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: tag).map { String(tag[$0]) }
        }
        guard let major = group(1).flatMap(Int.init), let minor = group(2).flatMap(Int.init),
              let patch = group(3).flatMap(Int.init) else { return nil }
        let stable = group(4) == nil
        return AppVersion(major: major, minor: minor, patch: patch, stable: stable,
                          build: group(5).flatMap(Int.init) ?? assetBuild ?? 0)
    }

    nonisolated static func bundle(_ info: [String: Any]) -> AppVersion? {
        guard let short = info["CFBundleShortVersionString"] as? String,
              let build = (info["CFBundleVersion"] as? String).flatMap(Int.init),
              let base = parse(tag: short) else { return nil }
        let channel = info["KotoReleaseChannel"] as? String ?? ""
        return AppVersion(major: base.major, minor: base.minor, patch: base.patch,
                          stable: channel.isEmpty, build: build)
    }
}

nonisolated struct ReleaseAsset: Sendable, Equatable {
    let name: String
    let url: URL
    let size: Int64
}

nonisolated struct AppRelease: Sendable, Equatable, Identifiable {
    var id: String { tag }
    let tag: String
    let version: AppVersion
    let title: String
    let notes: String
    let page: URL
    let dmg: ReleaseAsset
    let checksums: ReleaseAsset?
}

nonisolated enum UpdateFailure: Error, Equatable {
    case network, rateLimited, badResponse, noRelease
    case tooLarge, checksumMissing, checksumMismatch
    case mountFailed, appMissing, wrongApp, notNewer, signature
    case notWritable, helperFailed, timedOut, cancelled
}

/// Разбор релизов GitHub: только то, что нужно для выбора обновления.
nonisolated enum UpdateCatalog {
    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int64 }
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool
        let html_url: URL
        let assets: [Asset]
    }

    nonisolated static let maximumDownload: Int64 = 400 * 1_024 * 1_024

    /// Допустимы только HTTPS-хосты GitHub: ссылка из JSON не должна уводить загрузку на чужой сервер.
    nonisolated static func isTrustedHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
            || host == "githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Возвращает самый новый выпуск, строго новее current; nil — обновлений нет.
    nonisolated static func newest(from data: Data, newerThan current: AppVersion) throws -> AppRelease? {
        guard data.count <= 2_000_000, let releases = try? JSONDecoder().decode([Release].self, from: data) else {
            throw UpdateFailure.badResponse
        }
        var best: AppRelease?
        for release in releases where !release.draft {
            guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") && $0.name.contains("arm64") }),
                  isTrustedHost(dmg.browser_download_url), dmg.size > 0, dmg.size <= maximumDownload else { continue }
            let assetBuild = buildNumber(inAssetName: dmg.name)
            guard let version = AppVersion.parse(tag: release.tag_name, assetBuild: assetBuild),
                  version > current else { continue }
            let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" })
                .flatMap { isTrustedHost($0.browser_download_url) && $0.size <= 65_536 ? $0 : nil }
            let candidate = AppRelease(
                tag: release.tag_name, version: version, title: release.name ?? release.tag_name,
                notes: summary(release.body ?? ""), page: release.html_url,
                dmg: ReleaseAsset(name: dmg.name, url: dmg.browser_download_url, size: dmg.size),
                checksums: sums.map { ReleaseAsset(name: $0.name, url: $0.browser_download_url, size: $0.size) })
            if best == nil || candidate.version > best!.version { best = candidate }
        }
        return best
    }

    /// Koto-0.1.0-14-arm64-preview-ci.dmg → 14.
    nonisolated static func buildNumber(inAssetName name: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"^Koto-\d+\.\d+\.\d+-(\d+)-arm64"#),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return Int(name[range])
    }

    /// Краткое описание: Markdown-разметка убирается, длина ограничивается.
    nonisolated static func summary(_ body: String) -> String {
        let plain = body.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#*>`- \t")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return plain.count <= 700 ? plain : String(plain.prefix(700)) + "…"
    }

    /// Строка SHA256SUMS: «<hex>  <имя файла>».
    nonisolated static func expectedHash(in sums: String, fileName: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "*" })
            if parts.count == 2, parts[1] == fileName, parts[0].count == 64,
               parts[0].allSatisfy(\.isHexDigit) { return parts[0].lowercased() }
        }
        return nil
    }
}

/// Запуск внешних утилит с жёстким тайм-аутом: зависший hdiutil/codesign не должен блокировать приложение.
nonisolated enum UpdateProcess {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let job = Job(continuation)
            DispatchQueue.global().async { job.execute(executable, arguments, timeout: timeout) }
        }
    }

    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<(status: Int32, output: String), Error>?
        private var expired = false
        init(_ continuation: CheckedContinuation<(status: Int32, output: String), Error>) { self.continuation = continuation }

        private func finish(_ result: Result<(status: Int32, output: String), Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }

        func execute(_ executable: String, _ arguments: [String], timeout: TimeInterval) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { finish(.failure(UpdateFailure.helperFailed)); return }
            // Сначала просим процесс завершиться, затем гарантированно возвращаем ошибку, даже если труба удерживается потомком.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                lock.lock(); expired = true; lock.unlock()
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 3) { [self] in finish(.failure(UpdateFailure.timedOut)) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            lock.lock(); let timedOut = expired && process.terminationReason == .uncaughtSignal; lock.unlock()
            finish(timedOut ? .failure(UpdateFailure.timedOut)
                   : .success((process.terminationStatus, String(decoding: data.prefix(65_536), as: UTF8.self))))
        }
    }
}

nonisolated enum UpdateInstaller {
    /// Скрипт-помощник: ждёт выхода приложения, меняет bundle атомарными mv и запускает новую версию.
    /// При любом сбое возвращает прежнюю копию. Аргументы передаются отдельно, без интерполяции в shell.
    nonisolated static let swapScript = """
    #!/bin/sh
    PID="$1"; NEW="$2"; TARGET="$3"; RELAUNCH="$4"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      i=$((i+1))
      if [ "$i" -gt 300 ]; then rm -rf "$NEW"; rm -f "$0"; exit 1; fi
      sleep 0.1
    done
    OLD="$TARGET.old-$$"
    if /bin/mv "$TARGET" "$OLD"; then
      if /bin/mv "$NEW" "$TARGET"; then
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        /bin/rm -rf "$OLD"
      else
        /bin/mv "$OLD" "$TARGET"
        /bin/rm -rf "$NEW"
      fi
    else
      /bin/rm -rf "$NEW"
    fi
    if [ "$RELAUNCH" = "1" ]; then /usr/bin/open "$TARGET"; fi
    /bin/rm -f "$0"
    """

    /// Проверяет SHA-256 загруженного DMG по SHA256SUMS.txt того же выпуска.
    nonisolated static func verify(dmg: URL, release: AppRelease, checksumsText: String?) throws {
        guard let checksumsText, let expected = UpdateCatalog.expectedHash(in: checksumsText, fileName: release.dmg.name) else {
            throw UpdateFailure.checksumMissing
        }
        guard let handle = try? FileHandle(forReadingFrom: dmg) else { throw UpdateFailure.badResponse }
        defer { try? handle.close() }
        var digest = SHA256()
        var total: Int64 = 0
        while let block = try? handle.read(upToCount: 1_048_576), !block.isEmpty {
            digest.update(data: block)
            total += Int64(block.count)
            if total > UpdateCatalog.maximumDownload { throw UpdateFailure.tooLarge }
        }
        guard total == release.dmg.size else { throw UpdateFailure.checksumMismatch }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateFailure.checksumMismatch }
    }

    /// Монтирует DMG, проверяет приложение и копирует его рядом с текущим для атомарной замены.
    /// Возвращает путь подготовленной копии. DMG всегда отсоединяется.
    nonisolated static func stage(dmg: URL, workDirectory: URL, target: URL, current: AppVersion,
                                  bundleIdentifier: String) async throws -> URL {
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateFailure.notWritable }
        let mount = workDirectory.appendingPathComponent("mount-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let attach = try await UpdateProcess.run("/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mount.path, dmg.path], timeout: 120)
        guard attach.status == 0 else { throw UpdateFailure.mountFailed }
        func detach() async {
            _ = try? await UpdateProcess.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"], timeout: 60)
            try? FileManager.default.removeItem(at: mount)
        }
        do {
            let app = mount.appendingPathComponent("Koto.app")
            guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
                throw UpdateFailure.appMissing
            }
            guard let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw UpdateFailure.wrongApp }
            guard let version = AppVersion.bundle(info), version > current else { throw UpdateFailure.notNewer }
            let check = try await UpdateProcess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120)
            guard check.status == 0 else { throw UpdateFailure.signature }
            let staged = parent.appendingPathComponent(".Koto-update-" + UUID().uuidString + ".app", isDirectory: true)
            let copy = try await UpdateProcess.run("/usr/bin/ditto", [app.path, staged.path], timeout: 300)
            guard copy.status == 0 else { try? FileManager.default.removeItem(at: staged); throw UpdateFailure.helperFailed }
            await detach()
            return staged
        } catch {
            await detach()
            throw error
        }
    }

    /// Запускает помощника отдельным процессом: он переживёт завершение приложения.
    nonisolated static func launchSwap(staged: URL, target: URL, processID: Int32, relaunch: Bool,
                                       workDirectory: URL) throws {
        let script = workDirectory.appendingPathComponent("swap-" + UUID().uuidString + ".sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        guard chmod(script.path, 0o700) == 0 else { throw UpdateFailure.helperFailed }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(processID), staged.path, target.path, relaunch ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateFailure.helperFailed }
    }
}
