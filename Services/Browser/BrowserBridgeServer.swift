import Foundation
import Network
import Observation
import Darwin

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Локальный authenticated bridge. Изменение transport не включает облако и не раскрывает token браузеру.
@MainActor @Observable
final class BrowserBridgeServer {
    static let shared = BrowserBridgeServer()
    var enabled: Bool {
        didSet {
            if persistence { UserDefaults.standard.set(enabled, forKey: "browserBridge.enabled") }
            if enabled { start() } else { stop() }
        }
    }
    private(set) var status = String(localized: "Browser bridge is off")
    @ObservationIgnored private let directoryOverride: URL?
    @ObservationIgnored private let persistence: Bool
    @ObservationIgnored private let makeEngine: () -> any TranslationEngine
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var listenerID = UUID()
    @ObservationIgnored private var clients: [UUID: BrowserBridgeClient] = [:]
    @ObservationIgnored private var token = ""
    @ObservationIgnored private var socketPath: String?
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var seenOrder: [String] = []

    init(directory: URL? = nil, makeEngine: @escaping () -> any TranslationEngine = { RoutingTranslationEngine() }) {
        directoryOverride = directory
        persistence = directory == nil
        self.makeEngine = makeEngine
        enabled = directory == nil && UserDefaults.standard.bool(forKey: "browserBridge.enabled")
    }

    func startIfEnabled() { if enabled { start() } }
    func start() {
        guard listener == nil else { return }
        do {
            let directory = try directoryOverride ?? PrivateStorage.bridgeDirectory()
            try PrivateStorage.ensureDirectory(directory)
            let path = directory.appendingPathComponent("bridge.sock").path
            // Не удаляем чужие regular files или symlinks на ожидаемом месте socket.
            var existing = stat()
            if lstat(path, &existing) == 0 {
                guard (existing.st_mode & S_IFMT) == S_IFSOCK, existing.st_uid == getuid() else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                unlink(path)
            }
            token = try PrivateStorage.token()
            try PrivateStorage.write(Data(token.utf8), to: directory.appendingPathComponent("bridge.token"))
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .unix(path: path)
            let service = try NWListener(using: parameters)
            let generation = UUID()
            listenerID = generation
            service.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.listenerID == generation && self.listener != nil, self.clients.count < 4 else { connection.cancel(); return }
                    let id = UUID()
                    let client = BrowserBridgeClient(id: id, connection: connection, token: self.token,
                        makeEngine: self.makeEngine, reserveID: { [weak self] value in self?.reserve(value) ?? false },
                        onClose: { [weak self] in self?.clients.removeValue(forKey: id) })
                    self.clients[id] = client
                    client.start()
                }
            }
            service.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listenerID == generation && self.listener != nil else { return }
                    switch state {
                    case .ready:
                        chmod(path, 0o600)
                        self.status = String(localized: "Browser bridge is ready")
                    case .failed:
                        self.status = String(localized: "Unable to start the browser bridge")
                        self.stop()
                    default: break
                    }
                }
            }
            listener = service
            socketPath = path
            service.start(queue: DispatchQueue(label: "dev.slipcast.koto.bridge"))
            status = String(localized: "Starting browser bridge…")
        } catch { status = String(localized: "Bridge unavailable: check the directory and restart Koto") }
    }
    func stop() {
        listenerID = UUID()
        listener?.cancel(); listener = nil
        let current = clients.values
        clients.removeAll()
        for client in current { client.close() }
        if let socketPath { unlink(socketPath) }
        socketPath = nil
        seen.removeAll(); seenOrder.removeAll()
        status = String(localized: "Browser bridge is off")
    }
    private func reserve(_ id: String) -> Bool {
        let normalized = id.lowercased()
        guard !seen.contains(normalized) else { return false }
        seen.insert(normalized); seenOrder.append(normalized)
        if seenOrder.count > 128 { seen.remove(seenOrder.removeFirst()) }
        return true
    }
}

@MainActor
private final class BrowserBridgeClient {
    let id: UUID
    private let connection: NWConnection
    private let token: String
    private let makeEngine: () -> any TranslationEngine
    private let reserveID: (String) -> Bool
    private let onClose: () -> Void
    private var decoder = BridgeFrameDecoder()
    private var authenticated = false
    private var closed = false
    private var pendingBytes = 0
    private var handshakeDeadline: Task<Void, Never>?
    private var partialDeadline: Task<Void, Never>?
    private var idleDeadline: Task<Void, Never>?
    private var jobs: [String: (Task<Void, Never>, any TranslationEngine)] = [:]

    init(id: UUID, connection: NWConnection, token: String, makeEngine: @escaping () -> any TranslationEngine,
         reserveID: @escaping (String) -> Bool, onClose: @escaping () -> Void) {
        self.id = id; self.connection = connection; self.token = token
        self.makeEngine = makeEngine; self.reserveID = reserveID; self.onClose = onClose
    }
    func start() {
        handshakeDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            if self?.authenticated == false { self?.close() }
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state { case .failed, .cancelled: self?.close(); default: break }
            }
        }
        connection.start(queue: DispatchQueue(label: "dev.slipcast.koto.bridge-client"))
        receive()
    }
    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                do {
                    if let data, !data.isEmpty {
                        let messages = try self.decoder.append(data)
                        for message in messages { self.handle(message) }
                        if self.decoder.hasPartialFrame && self.partialDeadline == nil {
                            self.partialDeadline = Task { [weak self] in
                                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                                self?.close()
                            }
                        } else if !self.decoder.hasPartialFrame {
                            self.partialDeadline?.cancel(); self.partialDeadline = nil
                        }
                    }
                    if done { try self.decoder.finish(); self.close(); return }
                    guard error == nil else { self.close(); return }
                    self.receive()
                } catch { self.close() }
            }
        }
    }
    private func handle(_ message: BridgeEnvelope) {
        guard !closed else { return }
        if !authenticated {
            guard message.type == .hello,
                  message.payload["origin"] == BridgeOrigin.allowed,
                  let provided = message.payload["token"], PrivateStorage.matches(provided, token) else {
                close(); return
            }
            authenticated = true
            handshakeDeadline?.cancel(); handshakeDeadline = nil
            send(BridgeEnvelope(id: message.id, type: .helloAck, payload: ["authenticated": "true"]))
            resetIdle()
            return
        }
        resetIdle()
        switch message.type {
        case .ping: send(BridgeEnvelope(id: message.id, type: .pong))
        case .cancel:
            if let target = message.payload["requestID"], let (task, engine) = jobs.removeValue(forKey: target) {
                task.cancel(); engine.cancel()
                send(BridgeEnvelope(id: target, type: .error, payload: ["code":"cancelled"]))
            }
            send(BridgeEnvelope(id: message.id, type: .pong))
        case .translate:
            guard let origin = message.payload["pageOrigin"], TranslationPrivacy.browserOriginAllowed(origin) else { fail(message.id, "excluded_page"); return }
            guard jobs.count < 4 else { fail(message.id, "busy"); return }
            guard reserveID(message.id) else { fail(message.id, "duplicate_request"); return }
            guard let text = message.payload["text"], text.count <= 20_000,
                  let target = message.payload["target"], Self.languageID(target) else { fail(message.id, "invalid_request"); return }
            let source = message.payload["source"] ?? "auto"
            guard source == "auto" || Self.languageID(source) else { fail(message.id, "invalid_language"); return }
            let engine = makeEngine()
            let task = Task { [weak self] in
                guard let self else { return }
                defer { self.jobs.removeValue(forKey: message.id) }
                do {
                    let request = try TranslationRequest(text: text,
                        source: source == "auto" ? nil : TranslationLanguage(id: source),
                        target: TranslationLanguage(id: target), context: .browser)
                    let readiness = try await engine.readiness(for: request)
                    try Task.checkCancellation()
                    guard case .installed(let resolved) = readiness else { self.fail(message.id, "models_missing"); return }
                    let result = try await engine.translate(resolved)
                    try Task.checkCancellation()
                    guard !self.closed else { return }
                    self.send(BridgeEnvelope(id: message.id, type: .translated, payload: ["text": result.text]))
                } catch {
                    if !Task.isCancelled {
                        // Отказ session после успешной availability — тот же сценарий
                        // подготовки языков; сырые ошибки и исходный текст в RPC не уходят.
                        let code: String
                        switch error as? TranslationFailure {
                        case .some(.modelsNotInstalled): code = "models_missing"
                        case .some(.cloudNotAllowed): code = "cloud_not_allowed"
                        default: code = "translation_failed"
                        }
                        self.fail(message.id, code)
                    }
                }
            }
            jobs[message.id] = (task, engine)
        default: close()
        }
    }
    private static func languageID(_ value: String) -> Bool {
        value.count <= 32 && value.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil
    }
    private func fail(_ id: String, _ code: String) { send(BridgeEnvelope(id: id, type: .error, payload: ["code": code])) }
    private func send(_ value: BridgeEnvelope) {
        guard !closed, let data = try? BridgeFrameDecoder.encode(value), pendingBytes + data.count <= 4_194_304 else { close(); return }
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.pendingBytes -= data.count
                if error != nil { self.close() }
            }
        })
    }
    private func resetIdle() {
        idleDeadline?.cancel()
        idleDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            self?.close()
        }
    }
    func close() {
        guard !closed else { return }
        closed = true
        handshakeDeadline?.cancel(); partialDeadline?.cancel(); idleDeadline?.cancel()
        for (task, engine) in jobs.values { task.cancel(); engine.cancel() }
        jobs.removeAll()
        connection.cancel()
        onClose()
    }
}
