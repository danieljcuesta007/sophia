//! Confusion-pair linters curated Harper lacks (blueprint §7.3). Spike 3 measured
//! that Harper 2.7 ships only the reverse of `weather→whether` (`the whether` →
//! `the weather`), so the pairs the LLM measurably misses live here, deterministic
//! and narrow by design: a rule that cannot fire on correct prose beats a rule
//! with recall.

use harper_core::linting::{Lint, LintKind, Linter, Suggestion};
use harper_core::{Document, Span};

/// `weather` used where `whether` is meant. Fires on `weather or not`, and on a
/// deliberation verb + `weather` + clause opener (`discuss weather we …`). Never
/// fires on `the weather`: the determiner breaks both patterns.
pub struct WeatherWhether;

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
        let words: Vec<(String, Span<char>)> = document
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

/// `its` used where `it's` (it is / it has) is meant — the miss Grammarly
/// caught and curated Harper 2.7 did not (measured 8/01 on the regression
/// sentence). Deliberately narrow: only patterns where the possessive reading
/// is implausible. `its important role` stays silent; `its important we...`
/// fires.
pub struct ItsIts;

/// Adjectives that read as predicates after `it's`. Each still needs a clause
/// opener after it (or end of text) so `its important role` never fires.
const PREDICATE_ADJS: &[&str] = &[
    "important", "good", "bad", "best", "better", "worse", "worst", "hard",
    "easy", "difficult", "possible", "impossible", "clear", "obvious",
    "likely", "unlikely", "true", "false", "okay", "ok", "fine", "over",
    "done", "ready", "worth", "crucial", "critical", "essential", "vital",
];

const AFTER_ADJ: &[&str] = &[
    "to", "that", "we", "you", "i", "they", "he", "she", "for", "because",
];

impl Linter for ItsIts {
    fn lint(&mut self, document: &Document) -> Vec<Lint> {
        let words: Vec<(String, Span<char>)> = document
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
            if word != "its" {
                continue;
            }
            let next = |k: usize| words.get(i + k).map(|(w, _)| w.as_str());
            let fires = match next(1) {
                Some("been") | Some("not") | Some("gonna") => true,
                Some("going") | Some("time") => next(2) == Some("to"),
                Some(adj) if PREDICATE_ADJS.contains(&adj) => match next(2) {
                    Some(after) => AFTER_ADJ.contains(&after),
                    None => true, // end of text: predicate reading
                },
                _ => false,
            };
            if fires {
                let template = document.get_span_content(span).to_vec();
                lints.push(Lint {
                    span: *span,
                    lint_kind: LintKind::WordChoice,
                    suggestions: vec![Suggestion::replace_with_match_case(
                        "it's".chars().collect(),
                        template,
                    )],
                    message: "Did you mean `it's` (it is)? `its` is the possessive."
                        .to_string(),
                    priority: 31,
                });
            }
        }
        lints
    }

    fn description(&self) -> &str {
        "Flags `its` where the contraction `it's` is meant."
    }
}

/// `your` used where `you're` is meant. Only the unambiguous frames.
pub struct YourYoure;

impl Linter for YourYoure {
    fn lint(&mut self, document: &Document) -> Vec<Lint> {
        let words: Vec<(String, Span<char>)> = document
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
            if word != "your" {
                continue;
            }
            let next = |k: usize| words.get(i + k).map(|(w, _)| w.as_str());
            let fires = match next(1) {
                // "your welcome" as a complete reply; "your welcome party" is
                // possessive, so require nothing (or a clause opener) after.
                Some("welcome") => matches!(next(2), None | Some("to")),
                Some("gonna") => true,
                Some("going") => next(2) == Some("to"),
                Some("not") => true,
                _ => false,
            };
            if fires {
                let template = document.get_span_content(span).to_vec();
                lints.push(Lint {
                    span: *span,
                    lint_kind: LintKind::WordChoice,
                    suggestions: vec![Suggestion::replace_with_match_case(
                        "you're".chars().collect(),
                        template,
                    )],
                    message: "Did you mean `you're` (you are)? `your` is the possessive."
                        .to_string(),
                    priority: 31,
                });
            }
        }
        lints
    }

    fn description(&self) -> &str {
        "Flags `your` where the contraction `you're` is meant."
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn its_fires_on_contraction_frames() {
        let mut linter = ItsIts;
        for wrong in [
            "i think its important we discuss this.",
            "its been a long day.",
            "its not what you think.",
            "its going to rain.",
            "its time to leave.",
        ] {
            let doc = Document::new_plain_english_curated(wrong);
            assert_eq!(linter.lint(&doc).len(), 1, "missed: {wrong}");
        }
    }

    #[test]
    fn its_stays_silent_on_possessives() {
        let mut linter = ItsIts;
        for clean in [
            "The company changed its important role in the market.",
            "The dog wagged its tail.",
            "Its time slot moved to noon.",
            "The tree shed its leaves.",
            "It's important that we go.",
        ] {
            let doc = Document::new_plain_english_curated(clean);
            assert!(linter.lint(&doc).is_empty(), "false positive on: {clean}");
        }
    }

    #[test]
    fn your_fires_and_stays_silent_correctly() {
        let mut linter = YourYoure;
        for wrong in ["your gonna love this.", "your not serious.", "your going to win."] {
            let doc = Document::new_plain_english_curated(wrong);
            assert_eq!(linter.lint(&doc).len(), 1, "missed: {wrong}");
        }
        for clean in [
            "your welcome party is tonight.",
            "bring your going-away gift.",
            "your book is here.",
        ] {
            let doc = Document::new_plain_english_curated(clean);
            assert!(linter.lint(&doc).is_empty(), "false positive on: {clean}");
        }
    }

    #[test]
    fn does_not_fire_on_correct_usage() {
        let mut linter = WeatherWhether;
        for clean in [
            "Can you check the weather?",
            "The weather is perfect today.",
            "I wonder whether we should leave.",
            "We planned around the weather forecast.",
            "Bad weather or sunshine, we ride.",
        ] {
            let doc = Document::new_plain_english_curated(clean);
            assert!(linter.lint(&doc).is_empty(), "false positive on: {clean}");
        }
    }

    #[test]
    fn fires_on_confused_usage() {
        let mut linter = WeatherWhether;
        for wrong in [
            "We discuss weather we should of hired more people.",
            "I don't know weather or not to go.",
            "She asked weather it was time.",
        ] {
            let doc = Document::new_plain_english_curated(wrong);
            assert_eq!(linter.lint(&doc).len(), 1, "missed: {wrong}");
        }
    }
}
