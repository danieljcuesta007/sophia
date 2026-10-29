# Sophia

A local-first writing companion for Chrome. Select text on any page and Sophia returns
spelling and grammar fixes, better word choices, and a word-density read, in a calm
marble-and-light panel. Everything runs on your machine: no account, no API key, no network
calls (the one outbound request is the Google Fonts stylesheet, with system fonts as fallback).

## Install (unpacked)

1. Open `chrome://extensions` and turn on **Developer mode**.
2. **Load unpacked** and pick the `sophia/` folder.
3. Pin Sophia from the puzzle-piece menu. After editing any file, press reload on its card.

Requirements: Chrome (or another Chromium browser) with Manifest V3. Nothing to build or install.

## What's here

| Path | What it is |
|---|---|
| `sophia/manifest.json` | Manifest V3 entry |
| `sophia/content/content.js` | The in-page panel (Shadow DOM), local engine, drawer |
| `sophia/popup/` | Toolbar popup: paste-and-analyze, quick settings, theme |
| `sophia/options/` | Full settings page |
| `sophia/data/quotes.json` | Quotes shown in the panel |
| `sophia.html` | Offline mockup: the visual source of truth |
| `SOPHIA_BUILD_BRIEF.md` | The spec, with the numbered build order |

Settings live in `chrome.storage.local` under `sophia-settings`. Three surfaces edit that one
object, so every write is read-modify-write.

Theme is System (follows macOS light/dark live), Dawn, or Dusk.

## Where the build stands

Steps 1-8 of the brief are done: panel, drag/resize, local engine, spelling and grammar,
thesaurus, drawer, dusk mode, and the System theme.

**Next: step 9.** Move `analyze()` out of `content.js` into `engine/index.js`, split into
`localAnalyze` and the empty `aiAnalyze` seam. That split is also what lets the planned macOS
writing layer share the same engine.

Known gaps: the spelling list is a small hand-written map rather than a full dictionary, and
the density and quote data could grow.

## License

MIT, see [LICENSE](LICENSE).
