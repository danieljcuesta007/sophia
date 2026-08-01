// Spike 3 gate: call sophia_lint from Swift over the C ABI and verify it flags
// weather→whether and quater→quarter in the §7.1 regression sentence in <50 ms.
import Foundation

struct Issue: Decodable {
    let start: Int
    let end: Int
    let anchor_text: String
    let kind: String
    let replacement: String?
    let message: String
    let source: String
}

func lint(_ text: String) -> [Issue] {
    guard let raw = sophia_lint(text) else { return [] }
    defer { sophia_free(raw) }
    let json = Data(bytes: raw, count: strlen(raw))
    return (try? JSONDecoder().decode([Issue].self, from: json)) ?? []
}

let regression = "Their going to the meeting tomorrow and i think its important we discuss weather we should of hired more people last quater."

// Warm: dictionary + rule-set load happens once, at agent launch in the real app.
let warmStart = Date()
sophia_warmup()
_ = lint(regression)
let warmMs = Date().timeIntervalSince(warmStart) * 1000

// Measured pass — this is the ambient-loop cost.
let start = Date()
let issues = lint(regression)
let elapsedMs = Date().timeIntervalSince(start) * 1000

print("first-call (load + lint): \(String(format: "%.1f", warmMs)) ms")
print("steady-state lint:        \(String(format: "%.2f", elapsedMs)) ms")
print("issues: \(issues.count)")
for i in issues {
    let fix = i.replacement ?? "-"
    print("  [\(i.kind)] \(i.anchor_text) -> \(fix)  (\(i.start)..\(i.end)) \(i.message)")
}

func flagged(_ anchor: String, _ replacement: String) -> Bool {
    issues.contains {
        $0.anchor_text == anchor
            && ($0.replacement?.lowercased() ?? "") == replacement
    }
}

let weatherOK = flagged("weather", "whether")
let quaterOK = flagged("quater", "quarter")
let fastOK = elapsedMs < 50

// Round-trip the offsets: the UTF-16 ranges must select the anchor text exactly.
let utf16 = Array(regression.utf16)
let offsetsOK = issues.allSatisfy { issue in
    guard issue.start <= issue.end, issue.end <= utf16.count else { return false }
    return String(utf16CodeUnits: Array(utf16[issue.start..<issue.end]),
                  count: issue.end - issue.start) == issue.anchor_text
}

print("")
print("weather->whether: \(weatherOK ? "PASS" : "FAIL")")
print("quater->quarter:  \(quaterOK ? "PASS" : "FAIL")")
print("under 50 ms:      \(fastOK ? "PASS" : "FAIL") (\(String(format: "%.2f", elapsedMs)) ms)")
print("utf16 offsets:    \(offsetsOK ? "PASS" : "FAIL")")
exit(weatherOK && quaterOK && fastOK && offsetsOK ? 0 : 1)
