import AppKit
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Один координатор владеет захватом и transient lens. Главное окно сохраняет собственный ввод.
@MainActor @Observable
final class CaptureCoordinator {
    let live = LiveTranslationCoordinator()
    var openLive: (() -> Void)?
    let manualModel = ManualTranslationModel(engine: RoutingTranslationEngine())
    let lensModel = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .capture)
    private(set) var message = String(localized: "Selection: ⌃⌥⌘T · Region: ⌃⌥⌘R")
    private(set) var captureBusy = false
    private(set) var hotkeyIssue: String?
    private(set) var accessibilityGranted = false
    private(set) var screenGranted = false
    /// Последняя ошибка захвата: окно показывает панель разрешений только для ошибок доступа.
    private(set) var failure: CaptureFailure?
    /// Команда, ожидающая разрешения: продолжится автоматически, как только доступ появится.
    private(set) var pendingCapture: PendingCapture?
    /// После запроса записи экрана macOS часто требует перезапуск приложения: тогда показываем кнопку.
    private(set) var screenAccessRequested = false
    /// Доступ запрошен, но macOS его не применила: показываем подсказки по исправлению (старая запись, копия вне «Программ»).
    private(set) var permissionHelpNeeded = false
    private(set) var resettingPermissions = false
    @ObservationIgnored private var lastRequestAt: Date?

    /// Копия запущена из загрузки или образа: macOS не сохраняет для неё разрешения.
    var runsOutsideApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }
    var reopenMain: (() -> Void)?
    var hotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeysEnabled, forKey: "capture.hotkeysEnabled")
            configureHotkeys()
        }
    }

    @ObservationIgnored private let serviceProvider = CaptureServiceProvider()
    @ObservationIgnored private let selectionService = SelectionCaptureService()
    @ObservationIgnored private let ocrService = ScreenOCRService()
    @ObservationIgnored private let selector = RegionSelector()
    @ObservationIgnored private let hotkeys = GlobalHotkeyService()
    @ObservationIgnored private var lens: CaptureLensController?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var permissionWatcher: Task<Void, Never>?
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var started = false

    init() {
        hotkeysEnabled = UserDefaults.standard.object(forKey: "capture.hotkeysEnabled") as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        rememberApplication(NSWorkspace.shared.frontmostApplication)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.rememberApplication(app) }
        }
        serviceProvider.receive = { [weak self] text in self?.receiveServiceText(text) }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        refreshPermissions()
        configureHotkeys()
        BrowserBridgeServer.shared.startIfEnabled()
    }

    func stop() {
        cancel()
        hotkeys.unregister()
        LocalRuntimeSupervisor.shared.stop()
        BrowserBridgeServer.shared.stop()
        live.stop()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        started = false
    }

    private func rememberApplication(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousApplication = application
        if TranslationPrivacy.excluded(application.bundleIdentifier) { live.pause() }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        lastRequestAt = Date(); permissionHelpNeeded = false
        // Только явная кнопка показывает TCC prompt; на старте приложение ничего не запрашивает.
        // C API объявляет постоянный ключ как mutable global. Используем его документированное значение,
        // чтобы не ослаблять strict concurrency ради неизменяемого ключа словаря.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    func requestScreen() {
        screenAccessRequested = true
        lastRequestAt = Date(); permissionHelpNeeded = false
        _ = CGRequestScreenCaptureAccess()
        if !CGPreflightScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    private func configureHotkeys() {
        hotkeys.unregister()
        hotkeyIssue = hotkeysEnabled ? hotkeys.register { [weak self] id in
            if id == 1 { self?.captureSelection() } else if id == 2 { self?.captureRegion() } else if id == 3 { self?.startLive() }
        } : nil
    }

    func captureSelection() {
        cancel()
        refreshPermissions()
        guard accessibilityGranted else {
            awaitPermission(for: .selection, failure: .accessibilityRequired)
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        guard let target else { showFailure(.noApplication); return }
        guard !TranslationPrivacy.excluded(target.bundleIdentifier) else { message = String(localized: "This app is excluded in privacy settings"); return }
        let id = beginOperation(message: String(localized: "Reading selected text…"))
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Из menu bar не активируем Koto перед чтением чужого focused element.
                let captured = try await selectionService.capture(application: target)
                guard operationID == id, !Task.isCancelled else { return }
                await translate(captured, id: id)
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                let issue = (error as? CaptureFailure) ?? .unavailable
                if issue == .accessibilityRequired { awaitPermission(for: .selection, failure: issue) } else { showFailure(issue) }
            }
        }
    }

    func receiveServiceText(_ text: String) {
        cancel()
        guard !TranslationPrivacy.excluded(previousApplication?.bundleIdentifier) else { message = String(localized: "This source is excluded in privacy settings"); return }
        let id = beginOperation(message: String(localized: "Received selected text through macOS Services…"))
        task = Task { [weak self] in
            guard let self else { return }
            await translate(CapturedText(text: text, anchor: CGRect(origin: NSEvent.mouseLocation, size: .zero)), id: id)
        }
    }

    func captureRegion() {
        cancel()
        refreshPermissions()
        guard screenGranted else { awaitPermission(for: .region, failure: .screenRequired); return }
        lens?.hide()
        let id = beginOperation(message: String(localized: "Select a region containing text. Press Esc to cancel."))
        // Таймер начнётся после выбора: пользователь не должен спешить с выделением.
        deadline?.cancel()
        deadline = nil
        selector.begin { [weak self] rect, screen in
            guard let self, operationID == id else { return }
            guard let rect, let screen else { cancel(); return }
            message = String(localized: "Recognizing text on this Mac…")
            startDeadline(id: id)
            // Окно с индикатором появляется сразу: первое обращение к записи экрана может занять время.
            showLens(anchor: rect)
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    // Окна selector уже убраны. Пауза даёт compositor закончить их удаление.
                    try await Task.sleep(for: .milliseconds(180))
                    let text = try await ocrService.recognize(selection: rect, screen: screen)
                    guard operationID == id, !Task.isCancelled else { return }
                    await translate(CapturedText(text: text, anchor: rect), id: id)
                } catch {
                    guard operationID == id, !Task.isCancelled else { return }
                    let issue = (error as? CaptureFailure) ?? .unavailable
                    if issue == .screenRequired { awaitPermission(for: .region, failure: issue) } else { showFailure(issue) }
                }
            }
        }
    }

    func cancel() {
        permissionWatcher?.cancel(); permissionWatcher = nil
        pendingCapture = nil
        // ID отзывается раньше закрытия окон, чтобы callback selector не запустил старую задачу.
        operationID = nil
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        selector.cancel()
        lensModel.cancel()
        captureBusy = false
        message = String(localized: "Capture cancelled.")
    }

    private func beginOperation(message: String) -> UUID {
        failure = nil
        lensModel.clear()
        let id = UUID()
        operationID = id
        captureBusy = true
        self.message = message
        startDeadline(id: id)
        return id
    }

    private func startDeadline(id: UUID) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, operationID == id else { return }
            cancel()
            message = String(localized: "Capture did not finish within 60 seconds. Try again.")
            showLens(anchor: CGRect(origin: NSEvent.mouseLocation, size: .zero))
        }
    }

    private func translate(_ captured: CapturedText, id: UUID) async {
        lensModel.clear()
        lensModel.sourceIdentifier = "auto"
        lensModel.targetIdentifier = manualModel.targetIdentifier
        lensModel.sourceText = captured.text
        await lensModel.loadLanguages()
        guard operationID == id, !Task.isCancelled else { return }
        deadline?.cancel(); deadline = nil
        operationID = nil
        captureBusy = false
        failure = nil
        message = AppLocalization.capturedCharacters(captured.text.count)
        showLens(anchor: captured.anchor)
        lensModel.submit()
    }

    /// Показывает панель разрешений и следит за доступом: выдача разрешения продолжает исходную команду.
    private func awaitPermission(for command: PendingCapture, failure issue: CaptureFailure) {
        showFailure(issue)
        waitForPermission(for: command)
    }

    /// Живой перевод: окно открывается сразу; без доступа к экрану оно показывает панель разрешений,
    /// а выбор области начинается сам, как только доступ выдан.
    func startLive() {
        refreshPermissions()
        // Повторное нажатие горячей клавиши выключает уже идущий перевод: он виден поверх других окон.
        if live.running { live.stop(); return }
        openLive?()
        guard screenGranted else { waitForPermission(for: .live); return }
        if !live.hasRegion { live.chooseRegion() }
    }

    func waitForPermission(for command: PendingCapture) {
        permissionWatcher?.cancel()
        pendingCapture = command
        permissionWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, let pending = self.pendingCapture else { return }
                self.refreshPermissions()
                guard pending.canResume(accessibility: self.accessibilityGranted, screen: self.screenGranted) else {
                    // Прошло несколько секунд после запроса, а доступа нет: типичные причины — устаревшая запись в списке или копия вне «Программ».
                    if let asked = self.lastRequestAt, Date().timeIntervalSince(asked) > 8 { self.permissionHelpNeeded = true }
                    continue
                }
                self.lens?.hide()
                switch pending {
                case .selection: self.captureSelection()
                case .region: self.captureRegion()
                case .live: self.live.chooseRegion()
                }
                return
            }
        }
    }

    /// Сбрасывает записи macOS именно для Koto и запрашивает доступ заново. Помогает, когда Koto включён в списке,
    /// но не получает доступ: запись относилась к другой сборке (ad hoc подпись меняется с каждой версией).
    func resetPermissions() {
        guard !resettingPermissions else { return }
        resettingPermissions = true
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.slipcast.koto"
        Task { [weak self] in
            for service in ["Accessibility", "ScreenCapture"] {
                _ = try? await UpdateProcess.run("/usr/bin/tccutil", ["reset", service, bundleID], timeout: 15)
            }
            guard let self else { return }
            self.resettingPermissions = false
            self.permissionHelpNeeded = false
            self.screenAccessRequested = false
            self.refreshPermissions()
            // Новый запрос: macOS покажет системное окно или откроет нужный раздел настроек.
            switch self.pendingCapture {
            case .region: self.requestScreen()
            default: self.requestAccessibility()
            }
        }
    }

    /// Перезапуск нужен после выдачи записи экрана: macOS применяет её к новому процессу.
    func relaunch() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
        guard (try? helper.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    private func showFailure(_ issue: CaptureFailure) {
        cancel()
        failure = issue
        lensModel.clear()
        message = issue.errorDescription ?? String(localized: "Unable to capture text.")
        showLens(anchor: CGRect(origin: NSEvent.mouseLocation, size: .zero))
    }

    private func showLens(anchor: CGRect) {
        if lens == nil { lens = CaptureLensController(coordinator: self) }
        lens?.show(anchor: anchor)
    }

    func openCapturedInMain() {
        manualModel.sourceIdentifier = lensModel.sourceIdentifier
        manualModel.targetIdentifier = lensModel.targetIdentifier
        manualModel.sourceText = lensModel.sourceText
        reopenMain?()
        NSApp.activate(ignoringOtherApps: true)
    }
}
