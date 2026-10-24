import Foundation
import Observation
import Darwin

/// Разрешены только HTTPS-узлы поставщика весов; перевод и ключ runtime сюда не передаются.
enum ModelDownloadPolicy {
    nonisolated static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "huggingface.co" || host.hasSuffix(".huggingface.co")
            || host == "hf.co" || host.hasSuffix(".hf.co")
    }
}

/// Delegate хранит только Sendable callback. UI обновляется вызывающей стороной на MainActor.
final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let maximumBytes: Int64
    let progress: @Sendable (Int64) -> Void
    init(maximumBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.maximumBytes = maximumBytes; self.progress = progress
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {}
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes { downloadTask.cancel(); return }
        progress(totalBytesWritten)
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(ModelDownloadPolicy.allows) == true ? request : nil)
    }
}

enum ModelInstallationFailure: Error, LocalizedError {
    case catalog, response, space, unsafePath
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .catalog: "Каталог модели повреждён. Переустановите Koto из проверенного пакета."
        case .http(let status): "Сервер модели вернул HTTP \(status). Повторите установку позже."
        case .response: "Сервер не вернул полный файл модели. Повторите установку."
        case .space: "Недостаточно места: для загрузки и проверки модели освободите не менее 5,2 ГБ."
        case .unsafePath: "Каталог модели недоступен или содержит небезопасную ссылку."
        }
    }
}

/// Веса находятся только в Application Support после явного нажатия. Bundle содержит каталог и лицензию.
@MainActor @Observable
final class ModelInstallationManager {
    static let shared = ModelInstallationManager()
    typealias Download = @MainActor (URLSession, URL) async throws -> (URL, URLResponse)
    let specification: LocalModelManifest?
    private(set) var isInstalled = false
    private(set) var isBusy = false
    private(set) var isVerifying = false
    private(set) var downloadedBytes: Int64 = 0
    private(set) var status = "Модель не установлена"
    @ObservationIgnored private let directoryOverride: URL?
    @ObservationIgnored private let downloadOverride: Download?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?

    init(specification: LocalModelManifest? = nil, directory: URL? = nil, download: Download? = nil) {
        self.specification = specification ?? Self.bundledSpecification()
        directoryOverride = directory
        downloadOverride = download
        refresh()
    }
    private static func bundledSpecification() -> LocalModelManifest? {
        guard let url = Bundle.main.url(forResource:"manifest",withExtension:"json",subdirectory:"LocalModels"),
              let data = try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(LocalModelManifest.self,from:data)
    }
    var fraction: Double {
        guard let specification, specification.bytes > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(specification.bytes)))
    }
    var displayName: String { specification?.displayName ?? "Qwen3 4B Instruct 2507 · Q4_K_M" }
    var sizeDescription: String { ByteCountFormatter.string(fromByteCount:specification?.bytes ?? 0,countStyle:.decimal) }
    var progressDescription: String { ByteCountFormatter.string(fromByteCount:downloadedBytes,countStyle:.decimal) + " / " + sizeDescription }

    private func directory(for spec: LocalModelManifest) throws -> URL {
        guard LocalModelLocation.isSafe(spec) else { throw ModelInstallationFailure.catalog }
        if let directoryOverride { try PrivateStorage.ensureDirectory(directoryOverride); return directoryOverride }
        let support = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
        let base = support.appendingPathComponent("dev.slipcast.koto",isDirectory:true)
        try PrivateStorage.ensureDirectory(base)
        let models = base.appendingPathComponent("Models",isDirectory:true)
        try PrivateStorage.ensureDirectory(models)
        let directory = models.appendingPathComponent(spec.id,isDirectory:true)
        try PrivateStorage.ensureDirectory(directory)
        return directory
    }
    private func fileURL(for spec: LocalModelManifest) throws -> URL {
        try directory(for:spec).appendingPathComponent(spec.filename)
    }
    func refresh() {
        guard !isBusy else { return }
        guard let specification, LocalModelLocation.isSafe(specification),
              let file = try? fileURL(for:specification) else {
            isInstalled = false; status = "Модель не установлена"; return
        }
        var metadata = stat()
        isInstalled = lstat(file.path,&metadata) == 0 && (metadata.st_mode & S_IFMT) == S_IFREG
            && metadata.st_uid == getuid() && metadata.st_size == specification.bytes
        status = isInstalled ? "Файл модели установлен · целостность проверяется перед запуском" : "Модель не установлена"
    }
    func install() {
        guard !isBusy else { return }
        guard let spec = specification, LocalModelLocation.isSafe(spec), let url = spec.url,
              ModelDownloadPolicy.allows(url), url.host == "huggingface.co", url.query == nil,
              url.path == "/\(spec.repository ?? "")/resolve/\(spec.revision)/\(spec.filename)" else {
            status = ModelInstallationFailure.catalog.errorDescription ?? ""; return
        }
        let id = UUID(); operationID = id
        isBusy = true; isVerifying = false; downloadedBytes = 0
        status = "Загружаем модель…"
        operation = Task { [weak self] in
            guard let self else { return }
            var pending: URL?
            var networkTemporary: URL?
            let delegate = ModelDownloadDelegate(maximumBytes:spec.bytes) { [weak self] bytes in
                Task { @MainActor in
                    guard let self, self.operationID == id else { return }
                    self.downloadedBytes = min(spec.bytes, max(0, bytes))
                }
            }
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 3600
            let session = URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
            // Async download API разных версий Foundation может не передавать didWriteData
            // в пользовательский delegate. Счётчик самой task остаётся источником прогресса.
            let progressMonitor = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let tasks = await session.allTasks
                    guard let self, self.operationID == id else { return }
                    let received = tasks.map(\.countOfBytesReceived).max() ?? 0
                    if received > spec.bytes {
                        tasks.forEach { $0.cancel() }
                    } else {
                        self.downloadedBytes = max(self.downloadedBytes, received)
                    }
                    do { try await Task.sleep(for:.milliseconds(200)) } catch { return }
                }
            }
            defer {
                progressMonitor.cancel()
                session.invalidateAndCancel()
                if let networkTemporary { try? FileManager.default.removeItem(at:networkTemporary) }
                if let pending { try? FileManager.default.removeItem(at:pending) }
                if self.operationID == id {
                    self.operation = nil; self.operationID = nil; self.isBusy = false; self.isVerifying = false
                }
            }
            do {
                let directory = try self.directory(for:spec)
                let capacity = try directory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                if let capacity, capacity < spec.bytes * 2 + 134_217_728 { throw ModelInstallationFailure.space }
                let temporary: URL
                let response: URLResponse
                if let downloadOverride { (temporary,response) = try await downloadOverride(session,url) }
                else { (temporary,response) = try await session.download(from:url,delegate:delegate) }
                networkTemporary = temporary
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      response.url.map(ModelDownloadPolicy.allows) == true else { throw ModelInstallationFailure.response }
                guard http.statusCode == 200 else { throw ModelInstallationFailure.http(http.statusCode) }
                var downloaded = stat()
                guard lstat(temporary.path,&downloaded) == 0, (downloaded.st_mode & S_IFMT) == S_IFREG,
                      downloaded.st_uid == getuid(), downloaded.st_size == spec.bytes else { throw ModelInstallationFailure.response }
                let staging = directory.appendingPathComponent(".install-" + UUID().uuidString,isDirectory:true)
                try PrivateStorage.ensureDirectory(staging); pending = staging
                let file = staging.appendingPathComponent(spec.filename)
                try FileManager.default.moveItem(at:temporary,to:file); networkTemporary = nil
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
                self.isVerifying = true; self.downloadedBytes = spec.bytes; self.status = "Проверяем SHA-256 модели…"
                try await LocalRuntimeSupervisor.verifyFile(file,expected:spec.sha256,expectedBytes:spec.bytes,gguf:true)
                try Task.checkCancellation()
                let destination = directory.appendingPathComponent(spec.filename)
                var old = stat()
                if lstat(destination.path,&old) == 0 {
                    guard (old.st_mode & S_IFMT) == S_IFREG, old.st_uid == getuid() else { throw ModelInstallationFailure.unsafePath }
                }
                guard rename(file.path,destination.path) == 0 else { throw ModelInstallationFailure.unsafePath }
                self.isInstalled = true; self.status = "Модель установлена и проверена. Можно переводить локально."
            } catch {
                guard self.operationID == id else { return }
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    self.status = "Установка отменена · незавершённый файл удалён"
                } else if let issue = error as? ModelInstallationFailure { self.status = issue.errorDescription ?? "" }
                else if error is LocalRuntimeFailure { self.status = "Проверка модели не пройдена. Файл не установлен; повторите загрузку." }
                else { self.status = "Не удалось установить модель. Проверьте интернет и повторите попытку." }
            }
        }
    }
    func cancel() { operation?.cancel(); status = "Отменяем установку…" }
    func remove() {
        guard !isBusy, let specification else { return }
        do {
            let file = try fileURL(for:specification)
            var metadata = stat()
            if lstat(file.path,&metadata) == 0 {
                guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == getuid() else { throw ModelInstallationFailure.unsafePath }
                try FileManager.default.removeItem(at:file)
            }
            refresh()
        } catch { status = "Не удалось удалить файл модели. Проверьте доступ к каталогу Koto." }
    }
}
