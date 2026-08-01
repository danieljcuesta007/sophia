# Sophia Write

An ambient, system-wide writing layer for macOS. 100% local: errors are detected by a
deterministic Rust engine (Harper), rewrites come from Apple's on-device foundation
model. No account, no API key, no network calls.

Spec: see the companion blueprint repo (`sophia-write-blueprint`). Current status:
**Phase 1 ambient core + Phase 2 rewrite (⌘⇧K, on-device model) built; live
dogfood running.**

## Layout

```
core/                Rust workspace (Layer 1 of the hybrid engine)
  sophia-core/       Harper + Sophia's confusion-pair linters + dictionary suppression
  ffi/               C ABI staticlib: sophia_lint / sophia_warmup / sophia_free
platform-macos/      SwiftPM menu-bar agent (accessory / LSUIElement)
  Insertion/         Cadence's InsertionEngine, vendored verbatim (MIT, attributed)
  App/               AX watcher, overlay underlines, suggestion card, hotkeys, stores
spikes/              Phase 0 evidence (kept; results in each RESULTS.md)
tools/               build.sh (core + shell + selftest), package-app.sh (.app bundle)
```

## Build and run

```sh
tools/build.sh                 # cargo build --release, swift build, selftest
tools/package-app.sh           # → dist/Sophia Write.app (LSUIElement)
platform-macos/.build/release/sophia-write selftest   # headless invariants
SOPHIA_DEBUG=1 platform-macos/.build/release/sophia-write   # run with state logging
```

First run prompts for Accessibility permission (the agent is useless without it and
says so in the menu). Revoking it at runtime tears down all overlays; re-granting
restarts watching without a relaunch.

## Phase 0 spikes (evidence, kept)

| Spike | Question | Status |
|---|---|---|
| 1 — Underline positioning | Per-character screen bounds via AX in real apps? | **Done — viable.** `spikes/spike1-underline-bounds/RESULTS.md` |
| 2 — Xcode / `@Generable` | Guided generation needs the Xcode-only macros plugin | Deferred, non-blocking — prompt-constrained JSON measured at 100% anchor rate |
| 3 — Harper embedding | Rust staticlib linting under 50 ms via FFI | **Done — 0.32 ms.** `spikes/spike3-harper-ffi/RESULTS.md` |

## Ambient loop (Phase 1)

Focus enters a text field → 300 ms typing pause → Harper lints (<1 ms) → underlines
drawn by a click-through overlay at AX-reported bounds → click or `⌘⇧;` opens the
suggestion card → Accept applies through the insertion engine with anchor
re-verification — if the text moved, the edit is abandoned silently.

- Corrections underline solid; style marks dot — distinguishable by style, not hue.
- Secure text fields and deny-listed apps (password managers by default) get nothing.
- Personal dictionary at `~/.config/sophia/dictionary.json` (shared schema, designed
  for Cadence to adopt); per-app rules + pause in `~/.config/sophia/settings.json`.
- Keyboard: `⌘⇧K` rewrite selection · `⌘⇧;` next issue · `⌘⇧'` accept · `⌥⇧D` add word
  · `⌥⇧P` pause · `Esc` dismiss.

## Rewrite (Phase 2)

Select text anywhere and press `⌘⇧K`: a non-activating panel offers Proofread,
Concise, Professional, Friendly, Expand, or a free-text instruction. Apple's
on-device ~3B model rewrites the whole span (pre-warmed at launch; text never
leaves the machine); a word-level LCS diff in Rust recovers the edit spans; the
guards reject rewrites that change length wildly, merge sentences in Proofread,
or silently expand contractions (voice guard). Nothing applies until Accept.
Suggestion cards also gain a "Why?" button — the model explains the rule in one
sentence, on demand.

## Requirements

- macOS 14+ (measured on macOS 26, Apple Silicon)
- Xcode Command Line Tools (`swiftc`); full Xcode only for Phase 2 `@Generable`
- Rust toolchain (`cargo`)
- Accessibility permission at runtime

## Roadmap: deferred candidates

- **NotchPresence** (`~/notch-presence`, single-file Swift, MIT) — ambient activity
  signal in the camera notch. Deferred to Phase 3+: Sophia's current workloads are too
  fast to drive it honestly (Harper lints in <50 ms, warm rewrites in ~0.6 s), so today
  it would be decorative. Adopt when a long-running ambient process exists (style-profile
  learning, batch document review), driven by that progress as the 0–1 signal. Rules if
  it ships: it is the host's *only* activity signal (the ⌘⇧K panel loses its spinner),
  accent `#3F8A4F`, retune `bloomFloor` (0.12 is mic-RMS-tuned), verify by logging
  `phaseName` at session end — not by eye.

## Principles

- Never corrupt the user's document; every ambiguity resolves to doing nothing.
- Every Accessibility call is timeout-bounded; the target app must never freeze.
- No HTTP client linked into the binary — privacy is structural, not a promise
  (verified: `nm -u` shows no URLSession/CFNetwork/curl symbols).
- No Rust panic crosses the FFI; a panic degrades the lint to empty.
- No hardcoded user paths; portable from the first commit.

## Attribution

The insertion engine is vendored verbatim from
[Cadence](https://github.com/danieljcuesta007/cadence) (MIT). Grammar checking by
[Harper](https://crates.io/crates/harper-core) (Apache-2.0).
