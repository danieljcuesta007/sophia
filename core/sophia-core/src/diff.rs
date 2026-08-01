//! Word-level LCS diff (blueprint §7.5, Layer 3): recovers edit spans from a
//! whole-span rewrite so the model is never asked for offsets. Measured 4/4
//! anchorable spans in the Phase-0 probes; this is the production version.
//!
//! Hunks cover the inter-word whitespace on both sides (each hunk spans from
//! the end of the previous matched word to the start of the next), so applying
//! any subset of hunks to `before` reconstructs exactly, including spacing.
//! All offsets are UTF-16 code units.

use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Hunk {
    /// UTF-16 range in `before` this hunk replaces.
    pub start: usize,
    pub end: usize,
    pub before: String,
    pub after: String,
}

struct Tok {
    text_lower: String,
    /// UTF-16 offsets in the source string.
    start: usize,
    end: usize,
}

fn tokenize(s: &str) -> Vec<Tok> {
    let mut toks = Vec::new();
    let mut cur = String::new();
    let mut start = 0usize;
    let mut off = 0usize; // utf16 offset
    for ch in s.chars() {
        let w = ch.len_utf16();
        if ch.is_whitespace() {
            if !cur.is_empty() {
                toks.push(Tok { text_lower: cur.to_lowercase(), start, end: off });
                cur = String::new();
            }
        } else {
            if cur.is_empty() {
                start = off;
            }
            cur.push(ch);
        }
        off += w;
    }
    if !cur.is_empty() {
        toks.push(Tok { text_lower: cur.to_lowercase(), start, end: off });
    }
    toks
}

fn utf16_len(s: &str) -> usize {
    s.chars().map(|c| c.len_utf16()).sum()
}

fn utf16_slice(s: &str, start: usize, end: usize) -> String {
    let units: Vec<u16> = s.encode_utf16().collect();
    String::from_utf16_lossy(&units[start.min(units.len())..end.min(units.len())])
}

/// Word-level diff of `before` -> `after`. Case-insensitive matching so a
/// capitalization fix shows up as a hunk with the original casing preserved
/// in `before`/`after` text.
pub fn diff(before: &str, after: &str) -> Vec<Hunk> {
    let a = tokenize(before);
    let b = tokenize(after);

    // LCS DP over word tokens (spans are short — a selection, not a book).
    let (n, m) = (a.len(), b.len());
    let mut dp = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            dp[i][j] = if a[i].text_lower == b[j].text_lower {
                dp[i + 1][j + 1] + 1
            } else {
                dp[i + 1][j].max(dp[i][j + 1])
            };
        }
    }

    // Walk the DP, collecting matched pairs.
    let mut pairs = Vec::new();
    let (mut i, mut j) = (0usize, 0usize);
    while i < n && j < m {
        if a[i].text_lower == b[j].text_lower {
            pairs.push((i, j));
            i += 1;
            j += 1;
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            i += 1;
        } else {
            j += 1;
        }
    }

    // Case-only differences on matched pairs become their own hunks.
    let mut hunks: Vec<Hunk> = Vec::new();
    fn emit_gap(
        hunks: &mut Vec<Hunk>, before: &str, after: &str,
        a_from: usize, a_to: usize, b_from: usize, b_to: usize,
    ) {
        // Gap between matched anchors: replace before[a_from..a_to] with
        // after[b_from..b_to] (whitespace inclusive by construction).
        if a_from == a_to && b_from == b_to {
            return;
        }
        let bu: Vec<u16> = utf16_slice(before, a_from, a_to).encode_utf16().collect();
        let au: Vec<u16> = utf16_slice(after, b_from, b_to).encode_utf16().collect();
        if bu == au {
            return;
        }
        // Trim common WHITESPACE at the edges so the hunk sits on word
        // boundaries — "Their -> They're", never "ir -> y're" (trimming any
        // common char would split words) and never "of  -> have " (stray
        // spaces in the UI). Round-trip stays exact either way.
        let is_ws = |u: u16| char::from_u32(u as u32).is_some_and(|c| c.is_whitespace());
        let mut p = 0;
        while p < bu.len() && p < au.len() && bu[p] == au[p] && is_ws(bu[p]) {
            p += 1;
        }
        let mut s = 0;
        while s < bu.len() - p && s < au.len() - p
            && bu[bu.len() - 1 - s] == au[au.len() - 1 - s]
            && is_ws(bu[bu.len() - 1 - s])
        {
            s += 1;
        }
        hunks.push(Hunk {
            start: a_from + p,
            end: a_to - s,
            before: String::from_utf16_lossy(&bu[p..bu.len() - s]),
            after: String::from_utf16_lossy(&au[p..au.len() - s]),
        });
    }

    let mut prev_a_end = 0usize;
    let mut prev_b_end = 0usize;
    for &(ai, bi) in &pairs {
        emit_gap(&mut hunks, before, after, prev_a_end, a[ai].start, prev_b_end, b[bi].start);
        // Same word ignoring case; if the casing differs, that is a real edit.
        let before_word = utf16_slice(before, a[ai].start, a[ai].end);
        let after_word = utf16_slice(after, b[bi].start, b[bi].end);
        if before_word != after_word {
            hunks.push(Hunk {
                start: a[ai].start,
                end: a[ai].end,
                before: before_word,
                after: after_word,
            });
        }
        prev_a_end = a[ai].end;
        prev_b_end = b[bi].end;
    }
    emit_gap(&mut hunks, before, after,
             prev_a_end, utf16_len(before), prev_b_end, utf16_len(after));
    hunks
}

pub fn diff_json(before: &str, after: &str) -> Vec<u8> {
    serde_json::to_vec(&diff(before, after)).unwrap_or_else(|_| b"[]".to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn apply(before: &str, hunks: &[Hunk]) -> String {
        let mut units: Vec<u16> = before.encode_utf16().collect();
        let mut sorted: Vec<&Hunk> = hunks.iter().collect();
        sorted.sort_by(|x, y| y.start.cmp(&x.start));
        for h in sorted {
            let repl: Vec<u16> = h.after.encode_utf16().collect();
            units.splice(h.start..h.end, repl);
        }
        String::from_utf16_lossy(&units)
    }

    #[test]
    fn rewrite_round_trips_through_hunks() {
        let before = "Their going to the meeting tomorrow and i think its important.";
        let after = "They're going to the meeting tomorrow and I think it's important.";
        let hunks = diff(before, after);
        assert_eq!(apply(before, &hunks), after);
        assert!(hunks.iter().any(|h| h.before == "Their" && h.after == "They're"));
        assert!(hunks.iter().any(|h| h.before == "i" && h.after == "I"));
    }

    #[test]
    fn insertion_and_deletion_round_trip() {
        let before = "We should hired more people.";
        let after = "We should have hired people.";
        let hunks = diff(before, after);
        assert_eq!(apply(before, &hunks), after);
    }

    #[test]
    fn identical_strings_produce_no_hunks() {
        assert!(diff("same text", "same text").is_empty());
    }

    #[test]
    fn partial_application_keeps_spacing() {
        let before = "its good, don't you think";
        let after = "it is good, do not you think";
        let hunks = diff(before, after);
        // Apply only the first hunk; the rest of the string must be intact.
        let first = &hunks[..1];
        let out = apply(before, first);
        assert!(out.contains("don't you think"), "{out}");
    }
}
