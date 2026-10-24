import Foundation

/// Хранит только последнюю нормализованную строку; очередь кадров и история не накапливаются.
struct LiveFrameGate {
    private(set) var generation = UUID()
    private(set) var lastText: String?
    mutating func reset() -> UUID { generation = UUID(); lastText = nil; return generation }
    mutating func accept(_ text: String, generation incoming: UUID) -> Bool {
        guard incoming == generation, text.count <= 20_000 else { return false }
        let normalized = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !normalized.isEmpty else { lastText = nil; return false }
        guard normalized != lastText else { return false }
        lastText = normalized
        return true
    }
}
