# Spike 1 — Underline positioning: measured results

**Question:** can we get per-character-range screen bounds
(`kAXBoundsForRangeParameterizedAttribute`) for text in the apps the user actually
writes in?

**Answer: yes for every native app tested; no for Electron/contenteditable, where the
extension is the designated surface anyway. The ambient product is viable in its
specified form.**

Measured 2026-07-28 on macOS 26 (arm64), Accessibility permission granted to the
probing process. All probes read-only. Method: query bounds for 2-character ranges at
the start, middle, and end of real text; a result counts as *per-range* only if
multiple ranges return distinct origins (a single repeated rect means element/node
bounds, not text bounds).

## §13.1 Tier table, filled in

| App | Focused element | Per-range bounds | Method | Latency | Tier |
|---|---|---|---|---|---|
| TextEdit | `AXTextArea` (AppKit) | Yes — distinct rects per range | plain `AXBoundsForRange` | 0 ms | **Full** |
| Notes | `AXTextArea` (AppKit) | Yes | plain `AXBoundsForRange` | 0 ms | **Full** |
| Messages (input field) | `AXTextField` (TextKit) | Yes | plain `AXBoundsForRange` | 0 ms | **Full** |
| Mail (compose body) | `AXWebArea` → `AXStaticText` per paragraph (WebKit) | Yes — on the static-text nodes, offsets are node-local | plain `AXBoundsForRange` on descendants | 0–5 ms | **Full** (needs node-local offset mapping) |
| Chrome — `<textarea>` / `<input>` | `AXTextArea` | Yes — distinct rects across wrapped lines | plain `AXBoundsForRange` | 0 ms | **Full** |
| Chrome — contenteditable | `AXTextArea` (leaf, children collapsed) | No — zero rect; marker path returns container box | — | 0 ms | **Rewrite-only via AX; Full via the extension (DOM)** |
| Slack (Electron) | `AXTextArea` (leaf) | No — `AXBoundsForRange` returns success + zero rect; text-marker path returns the composer's node box. `--force-renderer-accessibility` relaunch did **not** enable inline text boxes. | — | 0 ms | **Rewrite-only** |
| Notion | desktop app **not installed** on this machine; used in Chrome | — | — | **Extension surface** (contenteditable) |
| Terminal (bonus) | `AXTextArea` | Yes | plain `AXBoundsForRange` | 0 ms | Full (not a writing target) |

## Findings that change engineering details

1. **WebKit bodies (Mail) expose text through per-paragraph `AXStaticText` nodes, not
   the web area.** Bounds work, but range offsets are local to each static-text node.
   The overlay needs a document-offset → (node, local-offset) mapping. The web area
   itself returns `chars=0`.
2. **Chromium advertises `AXBoundsForRange` but returns success with a zero rect.**
   Never trust the error code; validate the rect. The marker chain
   (`AXTextMarkerRangeForUIElement` → SPI `AXTextMarkerRangeCopyStartMarker` →
   `AXNextTextMarkerForTextMarker` stepping) produces *correct text ranges* (verified
   via `AXStringForTextMarkerRange`) but bounds degrade to the node box.
   `AXTextMarkerForIndex` is not implemented (silently returns whole-document markers).
3. **Passive AX text writes silently no-op in Chromium/Electron.** Setting
   `kAXSelectedTextRange` + `kAXSelectedTextAttribute` on an unfocused Slack composer
   returned err 0 twice and changed nothing. Insertion must go through the
   focused-element strategies Cadence already implements, and readback verification is
   mandatory — success codes lie.
4. **Electron's `AXManualAccessibility` accepts (err 0) but only enables the basic
   tree.** `AXEnhancedUserInterface` is rejected (-25208). No runtime lever found that
   gives Electron per-character bounds.
5. **Scrolled-away or off-screen text returns success with unusable rects** (observed
   negative-y rects in Messages transcript). The overlay must clip underlines to the
   element's visible bounds.
6. **Latency is a non-issue** everywhere: every bounds call measured 0–5 ms; marker
   stepping over a 61-char composer took 4 ms.

## Verdict for the product

The apps where Daniel actually writes prose — Mail, Notes, Messages, TextEdit, plus
browser textareas — are all **Full tier**. Underlines + cards + rewrite work as
specified. Electron apps (Slack) degrade exactly as the blueprint's tier design
anticipated: ⌘⇧K rewrite works (focused-element insertion), no underlines. The browser
gets Full tier through the extension (Phase 4), which owns contenteditable surfaces
(Notion, Docs, Slack-in-browser).

**No spec change required. Phase 1 can proceed.**

## Files

- `probe.swift` — focused-element probe: role, params, plain-range + marker-fallback bounds (JSON out)
- `probe-walk.swift` — walks a window/subtree probing every text-bearing node (`--from-focused`)
- `probe-marker.swift` — Chromium `AXTextMarkerForIndex` attempt (negative result, kept as evidence)
- `probe-marker2.swift` — marker-stepping probe with string verification (`probe-marker2 [AppName]`)
- `probe-find.swift` — passive by-value element finder + both bounds methods, no focus change
- `remove-text.swift` — surgical substring removal via AX selection (works in AppKit; no-ops in Chromium)
- `enable-ax.swift` — sets `AXManualAccessibility` / `AXEnhancedUserInterface` on the frontmost app
- `dump-tree.swift` — role-tree dumper
- Raw `result-*.json` files are gitignored: they contain window titles and message
  previews from the machine they ran on.

Build any of them: `xcrun swiftc -O <file>.swift -o <name>` (Command Line Tools are
sufficient; no Xcode needed for the probes).
