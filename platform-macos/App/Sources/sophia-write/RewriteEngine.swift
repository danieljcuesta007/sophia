// RewriteEngine — Layer 2 of the hybrid engine (blueprint §7.4): Apple's
// on-device model, invoked ONLY on explicit user action, pre-warmed at launch
// so the user never meets the 3.47 s cold path. The model rewrites whole
// spans; it never detects errors and is never asked for offsets — ranges come
// from the Rust diff (§7.5).
//
// Prompts are versioned template constants (§20), never string-built ad hoc.

import CSophiaFFI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum RewriteMode: String, CaseIterable {
    case proofread = "Proofread"
    case concise = "Concise"
    case professional = "Professional"
    case friendly = "Friendly"
    case expand = "Expand"

    /// PROMPT_V2 (2026-08-01). V1 measured in Phase-0 probe 4 (100% anchor
    /// rate); V2 adds the voice-preservation clause after the measured
    /// contraction-expansion defect (§7.5).
    var instruction: String {
        switch self {
        case .proofread:
            return "Correct spelling, grammar, and punctuation errors only. "
                + "Keep the author's wording, contractions, and sentence "
                + "structure exactly as written wherever they are not errors."
        case .concise:
            return "Rewrite the text to be more concise. Keep the author's "
                + "voice and meaning. Do not add new information."
        case .professional:
            return "Rewrite the text in a professional tone suitable for "
                + "work. Keep the meaning. Do not add new information."
        case .friendly:
            return "Rewrite the text in a warm, friendly tone. Keep the "
                + "meaning. Do not add new information."
        case .expand:
            return "Expand the text with a little more detail and flow, "
                + "staying true to the author's meaning and voice."
        }
    }

    /// Sane length-ratio bounds per mode (rewritten/original), the first
    /// hallucination tripwire.
    var ratioBounds: ClosedRange<Double> {
        switch self {
        case .proofread: return 0.75...1.35
        case .concise: return 0.25...1.05
        case .professional, .friendly: return 0.5...1.9
        case .expand: return 0.9...3.5
        }
    }
}

enum RewriteVerdict {
    case ok(String, [DiffHunk])
    case rejected(String)  // honest one-line reason, shown to the user
}

struct DiffHunk: Decodable, Equatable {
    let start: Int
    let end: Int
    let before: String
    let after: String

    /// A hunk that only expands a contraction or contracts an expansion —
    /// a voice change, not a correction (§7.5 voice guard).
    var isContractionStyle: Bool {
        func normalized(_ s: String) -> String {
            var t = " " + s.lowercased() + " "
            for (c, e) in [
                ("n't", " not"), ("'re", " are"), ("'ll", " will"),
                ("'ve", " have"), ("'m", " am"), ("it's", "it is"),
                ("that's", "that is"), ("what's", "what is"),
                ("there's", "there is"), ("he's", "he is"), ("she's", "she is"),
            ] {
                t = t.replacingOccurrences(of: c, with: e)
            }
            return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return (before.contains("'") || after.contains("'"))
            && normalized(before) == normalized(after)
    }
}

enum RewriteFFI {
    static func diff(before: String, after: String) -> [DiffHunk] {
        guard let raw = sophia_diff(before, after) else { return [] }
        defer { sophia_free(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        return (try? JSONDecoder().decode([DiffHunk].self, from: data)) ?? []
    }

    /// Apply a subset of hunks to the original (descending, exact).
    static func apply(_ hunks: [DiffHunk], to before: String) -> String {
        var units = Array(before.utf16)
        for h in hunks.sorted(by: { $0.start > $1.start }) {
            guard h.start <= h.end, h.end <= units.count else { continue }
            units.replaceSubrange(h.start..<h.end, with: Array(h.after.utf16))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}

/// The guards (§7.5): prefer doing nothing over corrupting meaning.
enum RewriteGuards {
    static func inspect(original: String, rewritten: String, mode: RewriteMode)
        -> RewriteVerdict
    {
        let cleaned = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .rejected("The model returned nothing.") }

        let ratio = Double(cleaned.count) / Double(max(original.count, 1))
        guard mode.ratioBounds.contains(ratio) else {
            return .rejected("The rewrite changed length too much — rejected.")
        }

        func sentenceCount(_ s: String) -> Int {
            s.split(whereSeparator: { ".!?".contains($0) })
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
        if mode == .proofread,
           sentenceCount(cleaned) != sentenceCount(original) {
            return .rejected("Proofread must not merge or split sentences — rejected.")
        }

        var hunks = RewriteFFI.diff(before: original, after: cleaned)
        guard !hunks.isEmpty else {
            return .rejected("No changes needed.")
        }

        if mode == .proofread {
            // Voice guard: unrequested contraction changes are style, and
            // Proofread is conservative by contract — suppress them.
            let kept = hunks.filter { !$0.isContractionStyle }
            guard !kept.isEmpty else { return .rejected("No changes needed.") }
            hunks = kept
            let final = RewriteFFI.apply(hunks, to: original)
            return .ok(final, hunks)
        }
        return .ok(cleaned, hunks)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
final class RewriteEngine {
    static let shared = RewriteEngine()
    private var session: LanguageModelSession?

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// Call once at launch (AC-15): the user never meets the cold path.
    func prewarm() {
        guard isAvailable, session == nil else { return }
        let s = LanguageModelSession(
            instructions: "You are a precise writing assistant. Follow the "
                + "instruction exactly. Output only the rewritten text — no "
                + "preamble, no quotes, no commentary.")
        s.prewarm()
        session = s
    }

    func rewrite(_ text: String, mode: RewriteMode, custom: String?) async throws
        -> String
    {
        prewarm()
        guard let session else { throw RewriteError.unavailable }
        let instruction = custom.map {
            "Rewrite the text per this instruction: \($0). Keep the meaning."
        } ?? mode.instruction
        let prompt = "\(instruction)\n\nText:\n\(text)"
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// One-sentence explanation of a deterministic suggestion (card "Why?").
    func explain(anchor: String, replacement: String, message: String) async throws
        -> String
    {
        prewarm()
        guard let session else { throw RewriteError.unavailable }
        let prompt = "In one short plain sentence for a writer, explain why "
            + "\"\(anchor)\" should be \"\(replacement)\" here. Rule hint: "
            + "\(message). No preamble."
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum RewriteError: Error { case unavailable }
}
#endif
