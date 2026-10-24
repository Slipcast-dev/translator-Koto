import AppKit
import Observation

/// Один координатор владеет захватом и transient lens. Главное окно сохраняет собственный ввод.
@MainActor @Observable
final class CaptureCoordinator {
    let live = LiveTranslationCoordinator()
    var openLive: (() -> Void)?
    let manualModel = ManualTranslationModel(engine: RoutingTranslationEngine())
    let lensModel = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .capture)
    private(set) var message = "Выделение: ⌃⌥⌘T · Область: ⌃⌥⌘R"
    private(set) var captureBusy = false
    private(set) var hotkeyIssue: String?
    private(set) var accessibilityGranted = false
    private(set) var screenGranted = false
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
        _ = CGRequestScreenCaptureAccess()
        if !CGPreflightScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    private func configureHotkeys() {
        hotkeys.unregister()
        hotkeyIssue = hotkeysEnabled ? hotkeys.register { [weak self] id in
            if id == 1 { self?.captureSelection() } else if id == 2 { self?.captureRegion() } else if id == 3 { self?.openLive?() }
        } : nil
    }

    func captureSelection() {
        cancel()
        refreshPermissions()
        guard accessibilityGranted else {
            showFailure(.accessibilityRequired)
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        guard let target else { showFailure(.noApplication); return }
        guard !TranslationPrivacy.excluded(target.bundleIdentifier) else { message = "Приложение исключено в настройках приватности"; return }
        let id = beginOperation(message: "Читаем выделенный текст…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Из menu bar не активируем Koto перед чтением чужого focused element.
                let captured = try await selectionService.capture(application: target)
                guard operationID == id, !Task.isCancelled else { return }
                await translate(captured, id: id)
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                showFailure((error as? CaptureFailure) ?? .unavailable)
            }
        }
    }

    func receiveServiceText(_ text: String) {
        cancel()
        guard !TranslationPrivacy.excluded(previousApplication?.bundleIdentifier) else { message = "Источник исключён в настройках приватности"; return }
        let id = beginOperation(message: "Получено выделение через Службы macOS…")
        task = Task { [weak self] in
            guard let self else { return }
            await translate(CapturedText(text: text, anchor: CGRect(origin: NSEvent.mouseLocation, size: .zero)), id: id)
        }
    }

    func captureRegion() {
        cancel()
        refreshPermissions()
        guard screenGranted else { showFailure(.screenRequired); return }
        lens?.hide()
        let id = beginOperation(message: "Выделите область с текстом. Esc — отмена.")
        // Таймер начнётся после выбора: пользователь не должен спешить с выделением.
        deadline?.cancel()
        deadline = nil
        selector.begin { [weak self] rect, screen in
            guard let self, operationID == id else { return }
            guard let rect, let screen else { cancel(); return }
            message = "Распознаём текст на Mac…"
            startDeadline(id: id)
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
                    showFailure((error as? CaptureFailure) ?? .unavailable)
                }
            }
        }
    }

    func cancel() {
        // ID отзывается раньше закрытия окон, чтобы callback selector не запустил старую задачу.
        operationID = nil
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        selector.cancel()
        lensModel.cancel()
        captureBusy = false
        message = "Захват отменён."
    }

    private func beginOperation(message: String) -> UUID {
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
            message = "Захват не завершился за 60 секунд. Повторите действие."
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
        message = "Захвачено \(captured.text.count) символов. Язык назначения — из главного окна."
        showLens(anchor: captured.anchor)
        lensModel.submit()
    }

    private func showFailure(_ issue: CaptureFailure) {
        cancel()
        lensModel.clear()
        message = issue.errorDescription ?? "Не удалось выполнить захват."
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
