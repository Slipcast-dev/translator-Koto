import Foundation

/// Пробелы и переносы принадлежат исходнику, а не модели. Ни один grapheme не режется по байтам.
enum TranslationPiece: Equatable, Sendable {
    case text(String)
    case literal(String)
    var original: String { switch self { case .text(let value), .literal(let value): value } }
}

enum TranslationChunker {
    /// 1700 UTF-8 bytes — консервативная верхняя граница token count для byte-fallback BPE.
    /// Оставляет место в контексте 4096 для инструкции, template и до 1536 output tokens.
    nonisolated static func pieces(_ text: String, maximumBytes: Int = 1700) -> [TranslationPiece] {
        precondition(maximumBytes >= 4)
        let characters = Array(text)
        var result: [TranslationPiece] = []
        var start = 0
        while start < characters.count {
            if characters[start].isWhitespace {
                var end = start + 1
                while end < characters.count && characters[end].isWhitespace { end += 1 }
                result.append(.literal(String(characters[start..<end])))
                start = end
                continue
            }
            var end = start
            var bytes = 0
            var wordBoundary: Int?
            var sentenceBoundary: Int?
            while end < characters.count {
                let character = characters[end]
                // Переносы сохраняются буквально: модель никогда не склеивает абзацы.
                if character.isNewline { break }
                let cost = String(character).utf8.count
                if bytes + cost > maximumBytes { break }
                bytes += cost
                if character.isWhitespace { wordBoundary = end }
                end += 1
                if ".!?。！？".contains(character) { sentenceBoundary = end }
            }
            // Чрезвычайно длинный grapheme (combining marks) не помещается: не теряем символы,
            // возвращаем его целиком, engine выдаст понятную ошибку до запроса.
            if end == start { end += 1 }
            if end < characters.count, !characters[end].isNewline {
                if let boundary = sentenceBoundary, boundary > start + (end - start) / 2 { end = boundary }
                else if let boundary = wordBoundary, boundary > start { end = boundary }
            }
            while end > start && characters[end - 1].isWhitespace { end -= 1 }
            if end == start { end += 1 }
            result.append(.text(String(characters[start..<end])))
            start = end
        }
        return result
    }

    /// Проверяются URL и шаблонные placeholders, которые нельзя переводить или терять.
    nonisolated static func protectedFragments(in text: String) -> [String] {
        let pattern = #"https?://[^\s<>\"\)]+|\{[A-Za-z_][A-Za-z0-9_.-]*\}|%\d*\$?[@dsf]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap {
            Range($0.range,in:text).map { String(text[$0]) }
        }
    }
    nonisolated static func preservesProtectedFragments(source: String, output: String) -> Bool {
        let fragments = protectedFragments(in:source)
        return Set(fragments).allSatisfy { fragment in
            source.components(separatedBy:fragment).count == output.components(separatedBy:fragment).count
        }
    }
}
