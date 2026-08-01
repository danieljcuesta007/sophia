// SentenceGroup — issues clustered by the sentence that contains them, so a
// sentence with several problems gets ONE card with a full diff and a single
// "Fix Sentence" action (one insertion, one anchor check, one undo unit).
// Interaction modeled on the sentence-correction card Daniel liked in
// Grammarly, rebuilt on Harper's deterministic spans.

import Foundation

struct SentenceGroup {
    /// UTF-16 range of the sentence in the field's text.
    let range: NSRange
    /// The sentence verbatim at lint time — re-verified before any apply.
    let sentence: String
    /// Issues inside the sentence, ascending by start offset.
    let issues: [Issue]

    var fixableCount: Int { issues.filter { $0.replacement != nil }.count }
}

enum SentenceGrouper {
    /// Cluster issues into the sentences that contain them. Issues that fall
    /// outside every sentence range (shouldn't happen) become singleton groups.
    static func groups(text: String, issues: [Issue]) -> [SentenceGroup] {
        guard !issues.isEmpty else { return [] }
        let ns = text as NSString
        var sentenceRanges: [NSRange] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            sentenceRanges.append(range)
        }

        var byIndex: [Int: [Issue]] = [:]
        var orphans: [Issue] = []
        for issue in issues.sorted(by: { $0.start < $1.start }) {
            if let at = sentenceRanges.firstIndex(where: {
                issue.start >= $0.location && issue.end <= $0.location + $0.length
            }) {
                byIndex[at, default: []].append(issue)
            } else {
                orphans.append(issue)
            }
        }

        var groups: [SentenceGroup] = byIndex.keys.sorted().map { at in
            let range = sentenceRanges[at]
            return SentenceGroup(
                range: range, sentence: ns.substring(with: range),
                issues: byIndex[at] ?? [])
        }
        groups += orphans.map {
            SentenceGroup(range: $0.utf16Range, sentence: $0.anchor_text, issues: [$0])
        }
        return groups.sorted { $0.range.location < $1.range.location }
    }

    /// The sentence with every replacement applied (descending by offset so
    /// earlier ranges stay valid). Issues whose anchor no longer matches its
    /// local range are skipped — never guessed at.
    static func corrected(_ group: SentenceGroup) -> String {
        var ns = group.sentence as NSString
        for issue in group.issues.sorted(by: { $0.start > $1.start }) {
            guard let replacement = issue.replacement else { continue }
            let local = NSRange(
                location: issue.start - group.range.location,
                length: issue.end - issue.start)
            guard local.location >= 0, local.location + local.length <= ns.length,
                  ns.substring(with: local) == issue.anchor_text
            else { continue }
            ns = ns.replacingCharacters(in: local, with: replacement) as NSString
        }
        return ns as String
    }
}
