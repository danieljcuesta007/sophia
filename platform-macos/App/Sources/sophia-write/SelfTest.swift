// SelfTest — headless invariants, Cadence's pattern (no XCTest on this
// machine). `sophia-write selftest` exercises the FFI boundary and the stores;
// exit 0 means every check passed.

import CSophiaFFI
import Foundation

enum SelfTest {
    /// Blueprint §7.1 — the permanent regression sentence.
    static let regression =
        "Their going to the meeting tomorrow and i think its important we discuss "
        + "weather we should of hired more people last quater."

    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ pass: Bool, _ detail: String = "") {
            print("\(pass ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if !pass { failures += 1 }
        }

        // AC-3: the two canonical flags, through the real FFI, under budget.
        sophia_warmup()
        _ = LintService.lintNow(regression, optsJSON: "{}")
        let start = Date()
        let issues = LintService.lintNow(regression, optsJSON: "{}")
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        func flagged(_ anchor: String, _ replacement: String) -> Bool {
            issues.contains {
                $0.anchor_text == anchor
                    && ($0.replacement?.lowercased() ?? "") == replacement
            }
        }
        check("weather->whether flagged", flagged("weather", "whether"))
        check("quater->quarter flagged", flagged("quater", "quarter"))
        check("steady-state lint < 50 ms", elapsedMs < 50,
              String(format: "%.2f ms", elapsedMs))

        // Offsets are UTF-16 and must round-trip exactly (underline anchoring).
        let utf16 = Array(regression.utf16)
        let offsetsOK = issues.allSatisfy { issue in
            guard issue.start <= issue.end, issue.end <= utf16.count else { return false }
            return String(
                utf16CodeUnits: Array(utf16[issue.start..<issue.end]),
                count: issue.end - issue.start) == issue.anchor_text
        }
        check("utf16 offsets round-trip", offsetsOK)

        // AC-13 groundwork: hostile inputs must not kill the process — reaching
        // the next line is the assertion.
        _ = LintService.lintNow(
            String(repeating: "\u{FFFD}\0", count: 10), optsJSON: "not json at all")
        check("hostile input survives the FFI", true)

        // AC-9 half 1: a dictionary term suppresses its spelling flag.
        let flaggedBare = LintService.lintNow("I met Addisuna yesterday.", optsJSON: "{}")
            .contains { $0.anchor_text == "Addisuna" }
        let suppressed = !LintService.lintNow(
            "I met Addisuna yesterday.", optsJSON: #"{"dictionary":["Addisuna"]}"#)
            .contains { $0.anchor_text == "Addisuna" }
        check("dictionary suppresses spelling flag", flaggedBare && suppressed)

        // Sentence card: grouping + corrected-sentence builder over real lint
        // output. Every fixable issue lands in one group and one insertion.
        let groups = SentenceGrouper.groups(text: regression, issues: issues)
        check("regression sentence forms one group", groups.count == 1,
              "\(groups.count) groups")
        if let group = groups.first {
            let fixed = SentenceGrouper.corrected(group)
            let expectations = ["They're", "I think", "whether", "should have", "quarter"]
            check("corrected sentence applies all fixes",
                  expectations.allSatisfy { fixed.contains($0) }
                      && !fixed.contains("quater"),
                  fixed)
        }

        // Stores: settings round-trip + per-app mode logic (AC-10 logic half).
        let settings = SettingsStore()
        check("password manager denied by default",
              settings.mode(for: "com.1password.1password") == .off)
        check("unknown app defaults to full",
              settings.mode(for: "com.example.someapp") == .full)

        print(failures == 0 ? "\nselftest: all checks passed"
                            : "\nselftest: \(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
