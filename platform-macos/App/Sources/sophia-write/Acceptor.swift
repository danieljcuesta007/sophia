// Acceptor — applies one suggestion through Cadence's insertion engine
// (blueprint §12.3). The non-negotiable rule lives here: every ambiguity
// resolves to doing nothing. Re-verify the anchor immediately before applying;
// if the text moved (the user typed while the card was open), abandon silently
// (AC-7). The document is never corrupted.

import Foundation
import SophiaInsertion

enum AcceptOutcome {
    case applied(InsertionResult)
    case abandonedTextMoved
    case abandonedSelectionFailed
    case abandonedNoReplacement
}

enum Acceptor {
    static func accept(issue: Issue, surface: TextSurface) -> AcceptOutcome {
        guard let replacement = issue.replacement else {
            return .abandonedNoReplacement
        }

        // 1. Anchor re-verification against a fresh read (§12.3 additional rule).
        guard let current = surface.readText() else { return .abandonedTextMoved }
        let ns = current as NSString
        let range = issue.utf16Range
        guard range.location + range.length <= ns.length,
              ns.substring(with: range) == issue.anchor_text
        else {
            return .abandonedTextMoved
        }

        // 2. Select the range; the selection must read back as the anchor —
        //    success codes lie (Spike 1), so an unverified selection aborts.
        guard surface.select(range: range, expecting: issue.anchor_text) else {
            return .abandonedSelectionFailed
        }

        // 3. Replace the verified selection via the engine: direct AX →
        //    paste+restore → clipboard+notify, readback-verified, secure-field
        //    refusing, deadline-bounded. One undoable unit in AppKit targets.
        let result = InsertionEngine().insert(replacement)
        return .applied(result)
    }

    /// Fix a whole sentence in one insertion: same contract, one anchor (the
    /// sentence), one selection, one undo unit. Safer than issue-by-issue —
    /// there is no intermediate state where offsets have shifted.
    static func accept(group: SentenceGroup, surface: TextSurface) -> AcceptOutcome {
        let fixed = SentenceGrouper.corrected(group)
        guard fixed != group.sentence else { return .abandonedNoReplacement }

        guard let current = surface.readText() else { return .abandonedTextMoved }
        let ns = current as NSString
        guard group.range.location + group.range.length <= ns.length,
              ns.substring(with: group.range) == group.sentence
        else {
            return .abandonedTextMoved
        }

        guard surface.select(range: group.range, expecting: group.sentence) else {
            return .abandonedSelectionFailed
        }

        let result = InsertionEngine().insert(fixed)
        return .applied(result)
    }
}
