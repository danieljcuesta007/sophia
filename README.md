# Sophia Write

An ambient, system-wide writing layer for macOS. 100% local: errors are detected by a
deterministic Rust engine (Harper), rewrites come from Apple's on-device foundation
model. No account, no API key, no network calls.

Spec: see the companion blueprint repo (`sophia-write-blueprint`). Current status:
**Phase 0 — feasibility spikes.**

## Phase 0 spikes

| Spike | Question | Status |
|---|---|---|
| 1 — Underline positioning | Can we get per-character screen bounds via the Accessibility API in real apps? | **Done — viable.** See `spikes/spike1-underline-bounds/RESULTS.md` |
| 2 — Xcode / `@Generable` | Guided generation needs the Xcode-only macros plugin | Pending |
| 3 — Harper embedding | Rust staticlib linting under 50 ms via FFI | Pending |

## Requirements

- macOS 15+ (measured on macOS 26, Apple Silicon)
- Xcode Command Line Tools (`swiftc`) for the spikes; full Xcode for Phase 2+
- Accessibility permission for any probe or the eventual agent
- Rust toolchain (Phase 0 Spike 3 onward)

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
- No HTTP client linked into the binary — privacy is structural, not a promise.
- No hardcoded user paths; portable from the first commit.
