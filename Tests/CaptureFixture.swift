import AppKit

/// Отдельное тестовое приложение содержит только публичные фразы.
/// В поставку Koto не входит; служит реальным внешним процессом для AX и OCR.
@MainActor
final class CaptureFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 160, width: 760, height: 460),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Koto Capture Fixture"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 760, height: 460))
        let title = NSTextField(labelWithString: "Koto · Capture test")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.frame = CGRect(x: 24, y: 400, width: 650, height: 40)
        content.addSubview(title)
        let scroll = NSScrollView(frame: CGRect(x: 24, y: 170, width: 710, height: 210))
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.font = .systemFont(ofSize: 28)
        text.string = "The cat is sleeping on the chair.\nGood morning from Koto."
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.setAccessibilityLabel("Контрольный текст Koto")
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        content.addSubview(scroll)
        let secureLabel = NSTextField(labelWithString: "Защищённое тестовое поле (пустое):")
        secureLabel.frame = CGRect(x: 24, y: 118, width: 600, height: 24)
        content.addSubview(secureLabel)
        let secure = NSSecureTextField(frame: CGRect(x: 24, y: 72, width: 400, height: 32))
        secure.setAccessibilityLabel("Пустое защищённое поле")
        content.addSubview(secure)
        let hint = NSTextField(labelWithString: "Выделите строку → ⌃⌥⌘T · OCR области → ⌃⌥⌘R · Cmd+Q закрывает fixture")
        hint.frame = CGRect(x: 24, y: 22, width: 710, height: 30)
        content.addSubview(hint)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: 0, length: 33))
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CaptureFixture {
    static func main() {
        let app = NSApplication.shared
        let delegate = CaptureFixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
