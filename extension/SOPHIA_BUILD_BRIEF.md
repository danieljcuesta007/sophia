# Sophia — Build Brief v2 (local first, free)

A Chrome extension (Manifest V3) that acts as a writing companion. It reads selected text and returns corrections, better word choices, and a word-density read, in a calm marble-and-light interface.

**Core principle: Sophia runs fully on the user's own machine and costs nothing.** Every v1 feature works offline with plain JavaScript. No account, no API key, no payment, no network calls. There is one clearly marked optional seam where a smarter AI engine plugs in later, but the extension must be complete and useful with that seam empty.

Design reference in this folder: **sophia.html**. It is a working offline mockup of the look, the colors, the popup, and the density ranking, and it proves all of this runs locally with zero API calls. Match its visual language exactly and port its analysis logic. Treat it as the source of truth for styling.

---

## What it does (v1, all local and free)

1. **Detect selection.** When the user selects text in any editable field (Gmail, Google Docs, plain textareas, contenteditable), show the floating Sophia panel near the selection.
2. **Corrections.** Spelling and basic grammar from local rules and a bundled dictionary, shown in a floating "Correct the sentence" card with inline changes and an "Accept all" button. Cover at least: misspellings, doubled words, lowercase "i", missing capital at sentence start, double spaces.
3. **Word choice.** Flag overused words and offer synonyms from a bundled thesaurus the user can click to copy or swap.
4. **Word density, ranked.** A leaderboard of the most-used meaningful words with exact counts and percent share. Three uses tag "heavy," four or more tag "too dense," and those words highlight inside the user's text.
5. **Counts.** Words, sentences, characters, reading time.
6. **Readability grade.** One number for how hard the text is to read, computed locally (a standard readability formula such as Flesch reading ease or grade level). Show it plainly with a short label like "Plain" or "Dense."
7. **Sentence rhythm.** Average sentence length, plus a gentle flag when sentences are all the same length (monotone) or one runs very long.
8. **Click-to-focus.** Clicking any word in the density ranking highlights every occurrence of it in the user's text.

---

## The window (movable, resizable, always balanced)

The Sophia panel is a floating window over the page.

- **Movable:** drag it by its header to anywhere on screen.
- **Resizable:** drag a corner handle to resize, within sensible **min and max bounds** so it never breaks.
- **Always balanced:** the composition must hold at any size. The marble light shaft and the long shadow recompute to the current dimensions, outer margins stay symmetric, the wordmark and accents stay centered in their zones, and sections reflow (stack or compress gracefully) rather than squish or clip. Nothing in the accent system gets cut off.
- **Remembers state:** last position and size persist in `chrome.storage.local` and restore next time.

---

## The menu / overview (the dropdown)

A hamburger button in the panel's top-left corner opens an overview drawer. This is the command center. It has two parts.

### A. Greeting + wisdom (top of the drawer)
- A time-aware greeting using the user's saved name: "Good morning, {name}", "Good evening, {name}", etc.
- A rotating quote underneath, drawn from a **bundled local list** that blends Stoic voices (Marcus Aurelius, Seneca, Epictetus) with a few lines from Proverbs. All public domain, shipped inside the extension, no network. Rotate on open or daily. Store the quotes as a local JSON file, easy to expand. Example entry shape: `{ "text": "...", "source": "Marcus Aurelius" }`.

### B. Page overview (the "all the major things" dashboard)
A live read of the **whole page**, not just the current selection. Sophia scans the readable/editable text on the page and shows:
- Total words on the page and reading time
- Top dense words across the entire page (the same ranking logic, page-wide)
- Number of open issues (corrections found) on the page
- Readability grade for the page overall
Refresh this when the drawer opens.

### C. Personalization controls (in the drawer)
- **Light / dark mode** toggle, on command.
- **Name** field, so Sophia can address the user. Saved to `chrome.storage.local`.
- The major feature toggles in one place (which checks are on).
- The disabled **"Use smarter AI suggestions"** toggle (off in v1, labeled "coming later").

---

## Dark mode ("marble by night")

A full dark variant. Charcoal stone instead of white marble, warm off-white text, pigments brightened slightly for contrast, sage stays the accent. Suggested tokens (tune to match the marble feel):

- Ink surface `#17181b`, raised surface `#1f2024`, lit edge `#26282c`
- Text `#ecead f`→ use `#ECEAE3`, secondary text `#A8A79E`, borders `#34363b`
- Terracotta `#C06A58`, Lapis `#6E93B5`, Sage `#9DB07F` (accent), Ochre `#CFA15E`

Drive it with a `data-theme="dark"` attribute on the root and CSS variables, so the toggle just flips the attribute. Respect the OS preference on first run, then honor the user's manual choice.

---

## The analysis engine (architecture matters)

All thinking goes through one interface so the local engine and a future AI engine are interchangeable:

```js
// engine/index.js
async function analyze(text, { useAI = false } = {}) {
  const local = localAnalyze(text); // synchronous, offline, free
  if (!useAI) return local;
  return aiAnalyze(text, local);     // optional, added later
}
```

- `localAnalyze(text)` does counts, density ranking, highlighting, dictionary spell-check, rule-based grammar, thesaurus synonyms, readability, and sentence rhythm. Port from sophia.html and extend.
- `aiAnalyze(text, local)` is a **stub** in v1: leave the file and function there, clearly commented as the future paid/optional engine, returning the local result for now. No network call.
- The AI toggle exists in the menu but is off and disabled in v1.

### Bundled data (ships inside the extension, no network)
- A spelling dictionary (common English word list)
- A thesaurus map for overused words (start from sophia.html, expand)
- A stopword list (in sophia.html)
- A quotes JSON (Stoics + Proverbs)

---

## Design system (match sophia.html exactly)

**Feel:** wisdom carved in stone. Marble, a single shaft of light, restraint. Clean true white, not cream.

**Color, with meaning** (light mode):
- Ink `#14140f` — text
- Marble `#f6f6f5` — page surface
- Marble bright `#ffffff` — cards
- Stone greys `#6b6b61`, `#c4c2b7`, `#dddbd0`
- Terracotta `#a14b3c` — spelling
- Lapis `#3f5d78` — grammar
- Sage `#76845e` — word choice (primary action)
- Ochre `#b0823a` — density warning

**Type:**
- Display/headings: Cormorant Garamond, light weights, restrained
- Body/interface: Hanken Grotesk
- Bundle font files locally if possible; Google Fonts is an acceptable fallback

**Signature elements to carry over:**
- Wordmark sets "Soph" regular and "ia" medium
- The "Correct the sentence" pop with inline colored diffs and Accept all / Dismiss
- The density leaderboard with thin bars, exact counts, percent share
- In-text highlighting of dense words (ochre wash for heavy, terracotta wash for too dense) via a backdrop layer

---

## Nice to have (add if straightforward, otherwise note as v1.1)
- A keyboard shortcut to summon or dismiss Sophia
- Per-site enable / disable, remembered
- "Copy clean version": copy the selected text with all accepted fixes applied

## Out of scope for v1 (future phases)
- The smarter AI engine (kept as a stub), the AI-detection gauge, cross-device sync

---

## Technical setup
- Manifest V3, no external host permissions in v1 (no network calls)
- Content script detects selection and injects the floating panel, popup, and menu drawer
- All analysis is synchronous and local, so results are instant
- `chrome.storage.local` holds: name, theme, panel position and size, per-site settings, toggles
- Options/menu reads and writes those preferences
- Walk me through loading it unpacked (chrome://extensions, Developer mode, Load unpacked)

---

## How to work
Build one piece at a time and explain each part as we go, because I am learning, not just copying. Suggested order:

1. Folder structure and `manifest.json` (no external permissions)
2. Content script: detect selection, inject an empty floating panel matching sophia.html
3. Make the panel movable, resizable with min/max bounds, balanced at any size, and persist position/size
4. The local engine: port counts, density ranking, highlighting; add readability and sentence rhythm
5. Dictionary spell-check and rule-based grammar into the corrections popup
6. Thesaurus synonyms into the word-choice section; click-to-focus on ranked words
7. The menu drawer: greeting + name, rotating quote, page overview dashboard
8. Dark mode via `data-theme` and CSS variables, with the toggle in the menu
9. The `analyze()` interface and the empty `aiAnalyze` stub, with the disabled AI toggle
10. Polish: keyboard focus, dismiss behavior, edge cases

Start with steps 1 through 3, confirm the window behaves, then continue.
