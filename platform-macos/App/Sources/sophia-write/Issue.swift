// Issue — the wire model from sophia_lint (blueprint §19 subset).
// Offsets are UTF-16 code units into the field's text, matching AX/NSString.

import Foundation

struct Issue: Decodable, Identifiable, Equatable {
    let start: Int
    let end: Int
    let anchor_text: String
    let kind: String
    let replacement: String?
    let message: String
    let source: String

    var id: String { "\(start)-\(end)-\(kind)" }
    var utf16Range: NSRange { NSRange(location: start, length: end - start) }

    /// Coarse class for rendering (AC-28: distinguishable by style, not hue alone).
    enum Coarse {
        case correction  // spelling, grammar, punctuation — solid underline
        case style       // word choice, enhancement — dotted underline
    }

    var coarse: Coarse {
        switch kind {
        case "Spelling", "Capitalization", "Grammar", "Punctuation", "Agreement",
             "Typo", "Repetition":
            return .correction
        default:
            return .style
        }
    }

    /// Only identity-style flags earn "Add to dictionary".
    var isDictionaryCandidate: Bool {
        kind == "Spelling" || kind == "Capitalization"
    }
}

enum IssueDecoder {
    static func decode(_ json: Data) -> [Issue] {
        (try? JSONDecoder().decode([Issue].self, from: json)) ?? []
    }
}
