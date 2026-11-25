import Foundation

enum GlossaryFormat: String, CaseIterable, Sendable { case json, csv }

/// Обмен словарём. Файл считается недоверенным: проверяются размер, схема, коды языков и каждая строка.
enum GlossaryExchange {
    enum Failure: Error { case size, format, record }
    /// 200 фраз по 2000/4000 символов в UTF-8 помещаются с запасом.
    nonisolated static let maximumBytes = 8_388_608
    nonisolated static let header = ["source", "target", "input", "output"]

    private struct Document: Codable {
        struct Phrase: Codable { let source: String; let target: String; let input: String; let output: String }
        let schema: Int
        let phrases: [Phrase]
    }

    static func encode(_ records: [PhraseRecord], format: GlossaryFormat) throws -> Data {
        switch format {
        case .json:
            let document = Document(schema: 1, phrases: records.map {
                .init(source: $0.source, target: $0.target, input: $0.input, output: $0.output)
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(document)
        case .csv:
            let rows = [header] + records.map { [$0.source, $0.target, $0.input, $0.output] }
            let text = rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
            return Data(text.utf8)
        }
    }

    static func decode(_ data: Data, format: GlossaryFormat) throws -> [PhraseRecord] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.size }
        let phrases: [[String]]
        switch format {
        case .json:
            guard let document = try? JSONDecoder().decode(Document.self, from: data), document.schema == 1 else {
                throw Failure.format
            }
            phrases = document.phrases.map { [$0.source, $0.target, $0.input, $0.output] }
        case .csv:
            guard var text = String(data: data, encoding: .utf8) else { throw Failure.format }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            var rows = try parse(text)
            guard rows.first == header else { throw Failure.format }
            rows.removeFirst()
            phrases = rows.map { $0.map(unguarded) }
        }
        guard !phrases.isEmpty, phrases.count <= 200 else { throw Failure.size }
        return try phrases.map { row in
            guard row.count == 4, isLanguage(row[0]), isLanguage(row[1]) else { throw Failure.record }
            return PhraseRecord(input: row[2], output: row[3], source: row[0], target: row[1])
        }
    }

    private static func isLanguage(_ value: String) -> Bool {
        value.range(of: "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*\\z", options: .regularExpression) != nil
    }

    /// Табличные редакторы выполняют ячейки, начинающиеся с = + - @, как формулы.
    /// При экспорте добавляется апостроф, при импорте он снимается.
    private static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
    private static func quote(_ value: String) -> String {
        var cell = value
        if let first = cell.first, formulaPrefixes.contains(first) || first == "'" { cell = "'" + cell }
        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func unguarded(_ value: String) -> String {
        guard value.first == "'", let second = value.dropFirst().first,
              formulaPrefixes.contains(second) || second == "'" else { return value }
        return String(value.dropFirst())
    }

    /// RFC 4180: кавычки, удвоение кавычек и переносы строк внутри ячейки.
    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        // Разбор по scalar: "\r\n" является одним Character и иначе не распознаётся.
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" { cell.unicodeScalars.append(scalar); index += 1 }
                    else { quoted = false }
                } else { cell.unicodeScalars.append(scalar) }
            } else if scalar == "\"", cell.isEmpty { quoted = true }
            else if scalar == "," { row.append(cell); cell = "" }
            else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                row.append(cell); cell = ""
                if row != [""] { rows.append(row) }
                row = []
                guard rows.count <= 201 else { throw Failure.size }
            } else { cell.unicodeScalars.append(scalar) }
            index += 1
        }
        guard !quoted else { throw Failure.format }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
