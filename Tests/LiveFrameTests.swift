import Foundation

@main
struct LiveFrameTests {
    static func main() throws {
        var gate = LiveFrameGate()
        let old = gate.generation
        var checks: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw NSError(domain: name, code: 1) }
            checks.append(name)
        }
        try check(gate.accept("Hello", generation: old), "first frame accepted")
        try check(!gate.accept(" Hello\n ", generation: old), "whitespace-only change deduplicated")
        try check(gate.accept("Hello world", generation: old), "changed frame accepted")
        let current = gate.reset()
        try check(!gate.accept("late old region", generation: old), "old region generation rejected")
        try check(gate.accept("Hello world", generation: current), "new region can translate same text")
        try check(!gate.accept("", generation: current) && gate.lastText == nil, "blank frame clears dedup state")
        try check(!gate.accept(String(repeating:"a",count:20001), generation: current), "oversize frame rejected")
        for index in 0..<10000 { _ = gate.accept("frame \(index)", generation: current) }
        try check(gate.lastText == "frame 9999", "only latest frame retained after long session")
        print(String(decoding: try JSONSerialization.data(withJSONObject:["status":"passed","count":checks.count,"tests":checks],
            options:[.prettyPrinted,.sortedKeys]), as: UTF8.self))
    }
}
