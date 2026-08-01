//! sophia-core-spike — Spike 3: Harper embedded behind the Cadence FFI pattern.
//!
//! C ABI, JSON payloads (blueprint §20). Rules enforced here:
//! - No Rust panic crosses the boundary: `catch_unwind` at every entry point;
//!   a panic degrades the lint to an empty issue list, it does not kill the agent.
//! - Every returned pointer is freed by an explicit `sophia_free`.
//! - Offsets in the JSON are UTF-16 code units, because that is what AX speaks.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

use harper_core::linting::{Lint, LintGroup, LintKind, Linter, Suggestion};
use harper_core::spell::FstDictionary;
use harper_core::{remove_overlaps, Dialect, Document};
use serde::Serialize;

/// `weather` used where `whether` is meant — the one confusion pair in the §7.1
/// regression sentence Harper's curated set does not cover (it ships only the
/// reverse, `the whether` → `the weather`). Deterministic and deliberately narrow:
/// flags `weather or not`, and `weather` immediately after a deliberation verb and
/// immediately before a clause opener (`discuss weather we …`). Never fires on
/// `the weather`, because the determiner breaks both patterns.
struct WeatherWhether;

const DELIBERATION_VERBS: &[&str] = &[
    "discuss", "discusses", "discussed", "discussing",
    "decide", "decides", "decided", "deciding",
    "determine", "determines", "determined", "determining",
    "wonder", "wonders", "wondered", "wondering",
    "debate", "debates", "debated", "debating",
    "consider", "considers", "considered", "considering",
    "ask", "asks", "asked", "asking",
    "know", "knows", "knew", "knowing",
    "question", "questions", "questioned", "questioning",
    "matter", "matters", "mattered",
];

const CLAUSE_OPENERS: &[&str] = &[
    "we", "i", "you", "they", "he", "she", "it", "to", "if",
];

impl Linter for WeatherWhether {
    fn lint(&mut self, document: &Document) -> Vec<Lint> {
        let words: Vec<(String, harper_core::Span<char>)> = document
            .tokens()
            .filter(|t| t.kind.is_word())
            .map(|t| {
                (
                    document.get_span_content_str(&t.span).to_lowercase(),
                    t.span,
                )
            })
            .collect();

        let mut lints = Vec::new();
        for (i, (word, span)) in words.iter().enumerate() {
            if word != "weather" {
                continue;
            }
            let next = |k: usize| words.get(i + k).map(|(w, _)| w.as_str());
            let or_not = next(1) == Some("or") && next(2) == Some("not");
            let verb_then_clause = i > 0
                && DELIBERATION_VERBS.contains(&words[i - 1].0.as_str())
                && next(1).is_some_and(|w| CLAUSE_OPENERS.contains(&w));
            if or_not || verb_then_clause {
                let template = document.get_span_content(span).to_vec();
                lints.push(Lint {
                    span: *span,
                    lint_kind: LintKind::WordChoice,
                    suggestions: vec![Suggestion::replace_with_match_case(
                        "whether".chars().collect(),
                        template,
                    )],
                    message: "Did you mean `whether` (a choice), not `weather` (the sky)?"
                        .to_string(),
                    priority: 31,
                });
            }
        }
        lints
    }

    fn description(&self) -> &str {
        "Flags `weather` where the conjunction `whether` is meant."
    }
}

/// One detected issue, the FFI subset of the blueprint §19 `Issue` model.
#[derive(Serialize)]
struct Issue {
    /// UTF-16 code-unit offsets into the linted string.
    start: usize,
    end: usize,
    /// Verbatim text at the span — re-verified by the shell before any apply.
    anchor_text: String,
    /// Harper's fine-grained kind (Debug form); the shell maps to coarse kinds.
    kind: String,
    replacement: Option<String>,
    message: String,
    source: &'static str,
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

/// Pure-Rust core of the lint, shared by the FFI entry point and tests.
pub fn lint_text(text: &str) -> Vec<u8> {
    let document = Document::new_plain_english_curated(text);
    let mut lints = engine()
        .lock()
        .map(|mut group| group.lint(&document))
        .unwrap_or_default();
    lints.extend(WeatherWhether.lint(&document));
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
        .collect();
    serde_json::to_vec(&issues).unwrap_or_else(|_| b"[]".to_vec())
}

/// Lint `text` (UTF-8, NUL-terminated). Returns a heap JSON string — an array of
/// issues — which the caller must release with [`sophia_free`]. Never panics
/// across the boundary; any internal failure returns `[]`.
///
/// # Safety
/// `text` must be a valid NUL-terminated C string, or null (returns `[]`).
#[no_mangle]
pub unsafe extern "C" fn sophia_lint(text: *const c_char) -> *mut c_char {
    let json = catch_unwind(AssertUnwindSafe(|| {
        if text.is_null() {
            return b"[]".to_vec();
        }
        match CStr::from_ptr(text).to_str() {
            Ok(s) => lint_text(s),
            Err(_) => b"[]".to_vec(),
        }
    }))
    .unwrap_or_else(|_| b"[]".to_vec());

    CString::new(json)
        .unwrap_or_else(|_| CString::new("[]").expect("static JSON"))
        .into_raw()
}

/// Pre-load the dictionary and rule set so the first real lint is fast.
#[no_mangle]
pub extern "C" fn sophia_warmup() {
    let _ = catch_unwind(|| {
        drop(engine().lock());
    });
}

/// Release a string returned by `sophia_lint`.
///
/// # Safety
/// `ptr` must be a pointer previously returned by `sophia_lint`, or null.
#[no_mangle]
pub unsafe extern "C" fn sophia_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The project's permanent regression sentence (blueprint §7.1). Every error in
    /// it was missed by the LLM on at least one measured run.
    const REGRESSION: &str = "Their going to the meeting tomorrow and i think its important we discuss weather we should of hired more people last quater.";

    fn issues_json() -> serde_json::Value {
        serde_json::from_slice(&lint_text(REGRESSION)).expect("valid JSON")
    }

    #[test]
    fn flags_weather_to_whether_and_quater_to_quarter() {
        let issues = issues_json();
        let issues = issues.as_array().expect("array");
        eprintln!("{}", serde_json::to_string_pretty(&issues).unwrap());

        let has = |anchor: &str, replacement: &str| {
            issues.iter().any(|i| {
                i["anchor_text"].as_str() == Some(anchor)
                    && i["replacement"].as_str().is_some_and(|r| {
                        r.eq_ignore_ascii_case(replacement)
                    })
            })
        };
        assert!(has("weather", "whether"), "missing weather->whether");
        assert!(has("quater", "quarter"), "missing quater->quarter");
    }

    #[test]
    fn weather_whether_does_not_fire_on_correct_usage() {
        let mut linter = WeatherWhether;
        for clean in [
            "Can you check the weather?",
            "The weather is perfect today.",
            "I wonder whether we should leave.",
            "We planned around the weather forecast.",
            "Bad weather or sunshine, we ride.",
        ] {
            let doc = Document::new_plain_english_curated(clean);
            assert!(
                linter.lint(&doc).is_empty(),
                "false positive on: {clean}"
            );
        }
        for wrong in [
            "We discuss weather we should of hired more people.",
            "I don't know weather or not to go.",
            "She asked weather it was time.",
        ] {
            let doc = Document::new_plain_english_curated(wrong);
            assert_eq!(linter.lint(&doc).len(), 1, "missed: {wrong}");
        }
    }

    #[test]
    fn steady_state_lint_under_50ms() {
        let _ = lint_text(REGRESSION); // warm: dictionary + rules load
        let start = std::time::Instant::now();
        let _ = lint_text(REGRESSION);
        let elapsed = start.elapsed();
        eprintln!("steady-state lint: {elapsed:?}");
        assert!(elapsed.as_millis() < 50, "lint took {elapsed:?}");
    }
}
