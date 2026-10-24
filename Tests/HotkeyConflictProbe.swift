import AppKit
import Foundation

/// Второй процесс пытается занять те же сочетания: проверяем реальный конфликт Carbon.
@main
struct HotkeyConflictProbe {
    static func main() throws {
        _ = NSApplication.shared
        let service = GlobalHotkeyService()
        let issue = service.register { _ in }
        service.unregister()
        let expectConflict = !CommandLine.arguments.contains("--expect-free")
        let repeatIssue = service.register { _ in }
        service.unregister()
        let passed = (issue != nil) == expectConflict && (repeatIssue != nil) == expectConflict
        let report: [String: Any] = ["conflict_detected": issue != nil, "message": issue ?? "registered",
                                     "expected_conflict": expectConflict, "status": passed ? "passed" : "failed",
                                     "repeat_registration_same_result": (issue != nil) == (repeatIssue != nil)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]), as: UTF8.self))
        if !passed { exit(1) }
    }
}
