//! sophia-core — Layer 1 of the hybrid engine (blueprint §7): deterministic
//! linting on Harper plus Sophia's own confusion-pair linters, with
//! personal-dictionary suppression. Pure Rust; the C ABI lives in `sophia-ffi`.
//!
//! Offsets in emitted issues are UTF-16 code units, because that is what AX
//! (and NSString) speak. Harper spans are `Span<char>`; a prefix-sum table
//! converts in O(n), verified to round-trip exactly from Swift (Spike 3).

pub mod confusions;
pub mod diff;

use std::sync::{Mutex, OnceLock};

use harper_core::linting::{Lint, LintGroup, Linter, Suggestion};
use harper_core::spell::FstDictionary;
use harper_core::{remove_overlaps, Dialect, Document};
use serde::{Deserialize, Serialize};

use confusions::{ItsIts, WeatherWhether, YourYoure};

/// One detected issue — the wire subset of the blueprint §19 `Issue` model.
#[derive(Serialize)]
pub struct Issue {
    /// UTF-16 code-unit offsets into the linted string.
    pub start: usize,
    pub end: usize,
    /// Verbatim text at the span — re-verified by the shell before any apply.
    pub anchor_text: String,
    /// Harper's fine-grained kind (Debug form); the shell maps to coarse kinds.
    pub kind: String,
    pub replacement: Option<String>,
    pub message: String,
    pub source: &'static str,
}

/// Options for one lint pass (the `opts` JSON of `sophia_lint`).
#[derive(Deserialize, Default)]
pub struct LintOptions {
    /// Personal-dictionary terms. Spelling/capitalization issues whose anchor
    /// matches a term case-insensitively are suppressed (blueprint §18: "stop
    /// telling me Addisuna is wrong"). Deeper harper-dictionary merging is a
    /// later upgrade; suppression is exact, cheap, and rebuild-free.
    #[serde(default)]
    pub dictionary: Vec<String>,
}

fn engine() -> &'static Mutex<LintGroup> {
    static ENGINE: OnceLock<Mutex<LintGroup>> = OnceLock::new();
    ENGINE.get_or_init(|| {
        Mutex::new(LintGroup::new_curated(
            FstDictionary::curated(),
            Dialect::American,
        ))
    })
}

/// Pre-load the dictionary and rule set (~300 ms once) so the first ambient
/// lint never pays it. Call at agent launch.
pub fn warmup() {
    drop(engine().lock());
}

/// Parse a `LintOptions` JSON string (the FFI `opts` payload). Lives here so
/// the FFI crate stays free of serde.
pub fn parse_options(json: &str) -> Option<LintOptions> {
    serde_json::from_str(json).ok()
}

fn lint_to_issue(lint: &Lint, source: &[char], utf16_prefix: &[usize]) -> Issue {
    let replacement = lint.suggestions.iter().find_map(|s| match s {
        Suggestion::ReplaceWith(chars) => Some(chars.iter().collect::<String>()),
        _ => None,
    });
    Issue {
        start: utf16_prefix[lint.span.start],
        end: utf16_prefix[lint.span.end],
        anchor_text: lint.get_str(source),
        kind: format!("{:?}", lint.lint_kind),
        replacement,
        message: lint.message.clone(),
        source: "harper",
    }
}

/// Does this issue name a personal-dictionary term? Only identity-style kinds
/// (spelling, capitalization) are suppressed — a dictionary term can still be
/// part of a grammar problem.
fn suppressed_by_dictionary(issue: &Issue, dictionary: &[String]) -> bool {
    if !(issue.kind == "Spelling" || issue.kind == "Capitalization") {
        return false;
    }
    let anchor = issue
        .anchor_text
        .trim_matches(|c: char| !c.is_alphanumeric());
    dictionary.iter().any(|t| t.eq_ignore_ascii_case(anchor))
}

/// Lint `text`, returning issues as serialized JSON (the FFI wire format).
pub fn lint_text(text: &str, opts: &LintOptions) -> Vec<u8> {
    let document = Document::new_plain_english_curated(text);
    let mut lints = engine()
        .lock()
        .map(|mut group| group.lint(&document))
        .unwrap_or_default();
    lints.extend(WeatherWhether.lint(&document));
    lints.extend(ItsIts.lint(&document));
    lints.extend(YourYoure.lint(&document));
    remove_overlaps(&mut lints);

    let source: Vec<char> = document.get_source().to_vec();
    // Prefix sums: utf16_prefix[i] = UTF-16 length of source[..i].
    let mut utf16_prefix = Vec::with_capacity(source.len() + 1);
    let mut acc = 0usize;
    utf16_prefix.push(0);
    for ch in &source {
        acc += ch.len_utf16();
        utf16_prefix.push(acc);
    }

    let issues: Vec<Issue> = lints
        .iter()
        .filter(|l| l.span.end <= source.len())
        .map(|l| lint_to_issue(l, &source, &utf16_prefix))
        .filter(|i| !suppressed_by_dictionary(i, &opts.dictionary))
        .collect();
    serde_json::to_vec(&issues).unwrap_or_else(|_| b"[]".to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The project's permanent regression sentence (blueprint §7.1). Every error
    /// in it was missed by the LLM on at least one measured run.
    const REGRESSION: &str = "Their going to the meeting tomorrow and i think its important we discuss weather we should of hired more people last quater.";

    fn issues(text: &str, opts: &LintOptions) -> Vec<serde_json::Value> {
        serde_json::from_slice::<serde_json::Value>(&lint_text(text, opts))
            .expect("valid JSON")
            .as_array()
            .expect("array")
            .clone()
    }

    #[test]
    fn regression_sentence_flags_weather_and_quater() {
        let found = issues(REGRESSION, &LintOptions::default());
        let has = |anchor: &str, replacement: &str| {
            found.iter().any(|i| {
                i["anchor_text"].as_str() == Some(anchor)
                    && i["replacement"]
                        .as_str()
                        .is_some_and(|r| r.eq_ignore_ascii_case(replacement))
            })
        };
        assert!(has("weather", "whether"), "missing weather->whether");
        assert!(has("quater", "quarter"), "missing quater->quarter");
    }

    #[test]
    fn dictionary_suppresses_spelling_flags() {
        let text = "I met Addisuna yesterday.";
        let baseline = issues(text, &LintOptions::default());
        assert!(
            baseline
                .iter()
                .any(|i| i["anchor_text"].as_str() == Some("Addisuna")),
            "expected Addisuna to be flagged without the dictionary"
        );
        let with_dict = issues(
            text,
            &LintOptions { dictionary: vec!["Addisuna".into()] },
        );
        assert!(
            !with_dict
                .iter()
                .any(|i| i["anchor_text"].as_str() == Some("Addisuna")),
            "dictionary term still flagged"
        );
    }

    #[test]
    fn steady_state_lint_under_50ms() {
        let opts = LintOptions::default();
        let _ = lint_text(REGRESSION, &opts); // warm: dictionary + rules load
        let start = std::time::Instant::now();
        let _ = lint_text(REGRESSION, &opts);
        let elapsed = start.elapsed();
        assert!(elapsed.as_millis() < 50, "lint took {elapsed:?}");
    }
}
