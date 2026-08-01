# Phase 1 status — built 2026-08-01, live dogfood pending

Verification state of the blueprint §31.6 acceptance criteria. "Headless" means
verified by `sophia-write selftest` or build-time checks on this machine; "live"
means it needs the agent running with Accessibility granted, which needs Daniel.

## Verified headless

| AC | Criterion | Evidence |
|---|---|---|
| AC-3 | weather→whether + quater→quarter via FFI < 50 ms | selftest: 0.30 ms |
| AC-9 (half) | Dictionary term stops being flagged in Sophia | selftest: suppression pass |
| AC-10 (logic) | Per-app rules persist (JSON store), pause immediate | selftest + code path |
| AC-13 (FFI half) | Hostile input degrades to empty, process survives | selftest |
| AC-25 | No HTTP client symbols in the binary | `nm -u`: none; `otool -L`: no CFNetwork |
| AC-29 | No hardcoded `/Users/<name>` | tree grep clean |
| AC-30 | No emojis in UI strings | source grep clean |

## Needs live testing (Daniel: grant Accessibility, run with SOPHIA_DEBUG=1)

| AC | Criterion | How to check |
|---|---|---|
| AC-4 | Underlines within 150 ms of the 300 ms pause | debug log prints "marked N/M in X ms" |
| AC-5 | Zero UI while actively typing | type fast in Notes; nothing should draw |
| AC-6 | Accept applies + readback verified in Tier-1 apps | accept a fix in TextEdit/Notes/Messages |
| AC-7 | Typing while card open abandons silently | open card, type, then accept — nothing applies |
| AC-8 | Nothing in secure fields / password managers | focus a password field |
| AC-9 (Cadence half) | Shared dictionary read by Cadence | needs a small Cadence change (below) |
| AC-11 | Idle < 1% CPU, < 150 MB RAM, 1 h soak | Activity Monitor |
| AC-12 | Revoke AX at runtime → clean teardown | toggle in System Settings; menu goes honest |
| AC-26/27/28 | Keyboard-only reach, VoiceOver-invisible overlay, Reduce Motion | manual pass |

## Known Phase-1 limitations (deliberate, documented)

1. **Mail (WebKit) is underline-only for now.** Reading and bounds work via the
   per-paragraph `AXStaticText` mapping (Spike 1), but WebKit web areas don't
   accept our document-offset selection writes, so Accept abandons (safely) in
   Mail. Needs live measurement of `kAXSelectedTextMarkerRange` semantics — the
   planned follow-up once the agent is running.
2. **Cadence does not yet read the shared dictionary.** Cadence keeps vocabulary
   in its SQLite store (`custom_vocabulary` setting); pointing it at
   `~/.config/sophia/dictionary.json` is a small upstream change but touches a
   shipped app, so it waits for a supervised session (repackage + live verify —
   see the 7/31 model-swap lesson).
3. **Scroll tracking is conservative.** Window move/resize and value changes
   invalidate overlays; pure scrolling inside some apps may briefly leave stale
   underlines until the next AX notification. Watch for it in dogfood.
4. **`⌘⇧K` rewrite is Phase 2.** The rewrite-only tier (Slack) therefore gets
   nothing visible yet — by design, not by bug.

## Dogfood plan (blueprint §32)

Start in **one app** (Notes or TextEdit, then Mail), alongside Grammarly, and keep
a miss-list. The first two entries are already known: curated Harper misses
`its→it's` (measured in Spike 3) and `tomorrow` placement — both fit the custom
linter pattern in `core/sophia-core/src/confusions.rs`.
