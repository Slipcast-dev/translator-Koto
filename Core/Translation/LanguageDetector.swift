import Foundation
import NaturalLanguage

/// Определение языка для коротких фраз и отдельных слов. Кандидаты ограничены языками движка,
/// поэтому даже «привет» даёт русский, а не «не удалось определить».
enum LanguageDetector {
    nonisolated static func detect(_ text: String, among candidates: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !candidates.isEmpty else { return nil }
        func has(_ id: String) -> Bool { candidates.contains { $0 == id || $0.hasPrefix(id + "-") } }
        func pick(_ id: String) -> String? { candidates.first { $0 == id } ?? candidates.first { $0.hasPrefix(id + "-") } }

        // Письменность однозначна для многих языков и надёжнее статистики на одном слове.
        var scripts = Set<String>()
        for scalar in trimmed.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0400...0x04FF: scripts.insert("cyrillic")
            case 0x0600...0x06FF: scripts.insert("arabic")
            case 0x0900...0x097F: scripts.insert("devanagari")
            case 0x0E00...0x0E7F: scripts.insert("thai")
            case 0x3040...0x30FF: scripts.insert("kana")
            case 0xAC00...0xD7AF: scripts.insert("hangul")
            case 0x4E00...0x9FFF: scripts.insert("han")
            default: scripts.insert("latin")
            }
        }
        if scripts == ["hangul"], has("ko") { return pick("ko") }
        if scripts == ["thai"], has("th") { return pick("th") }
        if scripts == ["devanagari"], has("hi") { return pick("hi") }
        if scripts.contains("kana"), has("ja") { return pick("ja") }
        if scripts == ["han"], has("zh") { return pick("zh") }
        if scripts == ["cyrillic"] {
            let ukrainian = trimmed.lowercased().contains { "іїєґ".contains($0) }
            if ukrainian, has("uk") { return pick("uk") }
            if has("ru") { return pick("ru") }
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map { NLLanguage(rawValue: $0) }
        recognizer.processString(trimmed)
        if let top = recognizer.languageHypotheses(withMaximum: 1).first?.key, let id = pick(top.rawValue) { return id }
        // Слово из латиницы без признаков языка чаще всего английское.
        if scripts == ["latin"], has("en") { return pick("en") }
        return nil
    }
}
