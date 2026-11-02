import Foundation
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Сетевая граница обновления. Подменяется в проверках, чтобы не обращаться к GitHub.
nonisolated struct UpdateTransport: Sendable {
    var fetch: @Sendable (URL) async throws -> Data
    var download: @Sendable (URL, URL, @escaping @Sendable (Int64) -> Void) async throws -> Void

    nonisolated static let releasesURL = URL(string: "https://api.github.com/repos/Slipcast-dev/translator-Koto/releases?per_page=20")!

    static let live = UpdateTransport(
        fetch: { url in
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Koto-Updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await LiveSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 || status == 429 { throw UpdateFailure.rateLimited }
            guard status == 200 else { throw UpdateFailure.network }
            return data
        },
        download: { url, destination, progress in
            let request = URLRequest(url: url, timeoutInterval: 30)
            let task = Task { try await LiveSession.shared.download(for: request) }
            // Прогресс и защита от зависания: если новые байты не приходят 60 секунд, загрузка отменяется.
            let monitor = Task {
                var last: Int64 = -1
                var stalledSince = ContinuousClock.now
                while !Task.isCancelled {
                    let received = await LiveSession.shared.allTasks.map(\.countOfBytesReceived).max() ?? 0
                    if received != last { last = received; stalledSince = .now; progress(received) }
                    else if stalledSince.duration(to: .now) > .seconds(60) { task.cancel(); return }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { monitor.cancel() }
            let (temporary, response) = try await withTaskCancellationHandler(
                operation: { try await task.value }, onCancel: { task.cancel() })
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.url.map(UpdateCatalog.isTrustedHost) == true else { throw UpdateFailure.network }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
        })

    /// Без cookies и кэша; редиректы допускаются только на хосты GitHub.
    private final class LiveSessionHolder: NSObject, URLSessionTaskDelegate, Sendable {
        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url.map(UpdateCatalog.isTrustedHost) == true ? request : nil)
        }
    }
    private enum LiveSession {
        static let shared: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 1_800
            return URLSession(configuration: config, delegate: LiveSessionHolder(), delegateQueue: nil)
        }()
    }
}

/// Состояние раздела «Обновление». Каждая стадия имеет тайм-аут, отмену и понятную ошибку.
@MainActor @Observable
final class UpdateModel {
    enum Phase: Equatable {
        case idle, checking, upToDate
        case available(AppRelease)
        case downloading, verifying, installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var checkedAt: Date?
    var failedRelease: AppRelease?

    @ObservationIgnored private let transport: UpdateTransport
    @ObservationIgnored private let current: AppVersion
    @ObservationIgnored private let target: URL
    @ObservationIgnored private let workDirectory: URL
    @ObservationIgnored private let bundleIdentifier: String
    @ObservationIgnored private let relaunch: Bool
    @ObservationIgnored private let processID: Int32
    @ObservationIgnored private let terminate: @MainActor () -> Void
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()

    init(transport: UpdateTransport = .live,
         current: AppVersion? = nil,
         target: URL = Bundle.main.bundleURL,
         workDirectory: URL? = nil,
         bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.slipcast.koto",
         relaunch: Bool = true,
         processID: Int32 = ProcessInfo.processInfo.processIdentifier,
         terminate: @escaping @MainActor () -> Void = {}) {
        self.transport = transport
        self.current = current ?? AppVersion.bundle(Bundle.main.infoDictionary ?? [:])
            ?? AppVersion(major: 0, minor: 0, patch: 0, stable: false, build: 0)
        self.target = target
        self.workDirectory = workDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/dev.slipcast.koto/Updates", isDirectory: true)
        self.bundleIdentifier = bundleIdentifier
        self.relaunch = relaunch
        self.processID = processID
        self.terminate = terminate
    }

    var isBusy: Bool {
        switch phase { case .checking, .downloading, .verifying, .installing: true; default: false }
    }
    var currentDescription: String { current.display }

    var statusText: String {
        switch phase {
        case .idle: String(localized: "Updates are checked only when you click the button.")
        case .checking: String(localized: "Checking for updates…")
        case .upToDate: String(localized: "You have the latest version.")
        case .available(let release): String(localized: "Update available: \(release.version.display)")
        case .downloading: String(localized: "Downloading update…")
        case .verifying: String(localized: "Verifying the update…")
        case .installing: String(localized: "Installing the update. Koto will restart.")
        case .failed(let message): message
        }
    }

    func check() {
        guard !isBusy else { return }
        start(.checking) { [self] id in
            let transport = self.transport
            let data = try await self.withTimeout(30) { try await transport.fetch(UpdateTransport.releasesURL) }
            let release = try UpdateCatalog.newest(from: data, newerThan: self.current)
            guard self.operationID == id else { return }
            self.checkedAt = Date()
            self.phase = release.map { .available($0) } ?? .upToDate
        }
    }

    func install(_ release: AppRelease) {
        guard !isBusy else { return }
        failedRelease = release
        start(.downloading) { [self] id in
            try PrivateStorage.ensureDirectory(self.workDirectory.deletingLastPathComponent())
            try PrivateStorage.ensureDirectory(self.workDirectory)
            let dmg = self.workDirectory.appendingPathComponent(release.dmg.name)
            var sums: Data?
            if let asset = release.checksums {
                let transport = self.transport
                sums = try await self.withTimeout(30) { try await transport.fetch(asset.url) }
            }
            let total = Double(release.dmg.size)
            try await self.transport.download(release.dmg.url, dmg) { [weak self] received in
                Task { @MainActor in
                    guard let self, self.operationID == id else { return }
                    self.progress = min(1, Double(received) / total)
                }
            }
            try Task.checkCancellation()
            self.phase = .verifying
            let checksumsText = sums.flatMap { String(data: $0, encoding: .utf8) }
            try await Task.detached(priority: .utility) {
                try UpdateInstaller.verify(dmg: dmg, release: release, checksumsText: checksumsText)
            }.value
            try Task.checkCancellation()
            self.phase = .installing
            let staged = try await UpdateInstaller.stage(
                dmg: dmg, workDirectory: self.workDirectory, target: self.target,
                current: self.current, bundleIdentifier: self.bundleIdentifier)
            try? FileManager.default.removeItem(at: dmg)
            guard self.operationID == id else { try? FileManager.default.removeItem(at: staged); return }
            try UpdateInstaller.launchSwap(staged: staged, target: self.target,
                processID: self.processID, relaunch: self.relaunch,
                workDirectory: self.workDirectory)
            // Помощник дожидается выхода процесса, заменяет bundle и сам запускает новую версию.
            self.terminate()
        }
    }

    func cancel() {
        operationID = UUID()
        operation?.cancel(); operation = nil
        if case .failed = phase { return }
        phase = .idle; progress = 0
    }

    private func start(_ initial: Phase, _ body: @escaping @MainActor (UUID) async throws -> Void) {
        let id = UUID()
        operationID = id
        phase = initial
        progress = 0
        operation = Task { [weak self] in
            guard let self else { return }
            do { try await body(id) }
            catch {
                guard self.operationID == id, !(error is CancellationError) else { return }
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Общий тайм-аут стадии: сетевой вызов не может висеть дольше заданного времени.
    private func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: .seconds(seconds)); throw UpdateFailure.timedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    nonisolated static func message(for error: Error) -> String {
        switch error as? UpdateFailure {
        case .rateLimited: String(localized: "GitHub temporarily limited requests. Try again later.")
        case .badResponse, .noRelease: String(localized: "The update server returned an unexpected response.")
        case .tooLarge, .checksumMismatch: String(localized: "The downloaded update failed verification and was not installed.")
        case .checksumMissing: String(localized: "The release has no checksum file, so the update was not installed.")
        case .mountFailed, .appMissing, .wrongApp: String(localized: "The update package is damaged or is not Koto.")
        case .notNewer: String(localized: "The package is not newer than the installed version.")
        case .signature: String(localized: "The update has an invalid code signature and was not installed.")
        case .notWritable: String(localized: "Koto cannot replace itself in this folder. Move it to Applications or install the update manually.")
        case .helperFailed: String(localized: "Unable to start the installer. Install the update manually from the release page.")
        case .timedOut: String(localized: "The operation took too long and was stopped. Try again.")
        case .cancelled: String(localized: "Update cancelled.")
        case .network, .none: String(localized: "Unable to reach the update server. Check your connection.")
        }
    }
}
