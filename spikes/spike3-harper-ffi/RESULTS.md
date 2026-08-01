# Spike 3 — Harper embedding via Rust staticlib + Swift FFI

**Date:** 2026-08-01 · **Verdict: GATE PASSED.** Harper embeds cleanly behind the
Cadence FFI pattern and lints the regression sentence from Swift in **0.32 ms** —
156x under the 50 ms budget (AC-3).

## Measured results (Apple Silicon, release build, LTO)

| Metric | Result |
|---|---|
| Steady-state `sophia_lint` from Swift | **0.32 ms** |
| First call (dictionary + rule-set load) | **309 ms** — do at agent launch, never in the ambient loop |
| Regression sentence issues found | 5: `Their→They're`, `i→I`, `weather→whether`, `should of→should have`, `quater→quarter` |
| `weather→whether` | PASS |
| `quater→quarter` | PASS |
| UTF-16 offsets round-trip from Swift | PASS (every span selects its anchor text exactly) |

Reproduce: `cargo test --release` in `core/`, then
`swiftc swift/main.swift -import-objc-header swift/sophia_core.h -L core/target/release -lsophia_core_spike -O -o swift/lint-test && ./swift/lint-test`

## What was learned (feeds Phase 1)

1. **`harper-core` 2.7.0 needs the `concurrent` feature** to be `Send+Sync`
   (its `LSend` marker is a no-op otherwise). Without it a global
   `Mutex<LintGroup>` will not compile — required for linting off a worker queue.
2. **Curated Harper does NOT cover `weather→whether`.** It ships only the reverse
   (`the whether` → `the weather`, a Weir rule). A custom `Linter`
   (`WeatherWhether`, ~60 lines) covers it deterministically: fires on
   `weather or not` and on deliberation-verb + `weather` + clause-opener;
   guarded against `the weather` by construction. False-positive tests included.
   → Pattern established for the rest of the blueprint §7.3 confusion-pair backlog.
3. **Curated Harper also missed `its→it's`** in the regression sentence (6th error;
   the gate only requires 2). First entry on the Harper rule backlog (§32's
   miss-list). Same custom-linter pattern applies.
4. **Emit UTF-16 offsets from Rust.** Harper spans are `Span<char>` (Unicode
   scalars); AX speaks UTF-16 code units. A prefix-sum table converts in O(n) and
   the Swift side verified every span round-trips exactly.
5. **`cargo test` does not produce the staticlib** — `cargo build --release` does.
   The `.a` links into a Swift binary with just `-import-objc-header` + `-L -l`;
   no extra frameworks needed.
6. **FFI contract held:** `catch_unwind` at every entry, panic degrades to `[]`
   (AC-13 groundwork), every pointer freed by `sophia_free`, JSON payloads.
   `crate-type = ["staticlib", "rlib"]`, no `cdylib` (Cadence's linker gotcha).

## Files

- `core/` — `sophia-core-spike` crate: `sophia_lint` / `sophia_warmup` / `sophia_free`
- `swift/main.swift` — Swift gate harness (exit 0 = gate passed)
- `swift/sophia_core.h` — C header for the bridge

Phase 0 status: Spike 1 done (ambient viable), Spike 3 done (this), Spike 2 (Xcode)
deferred and non-blocking — prompt-constrained JSON is the measured fallback.
