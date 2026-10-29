/**
 * Sophia – content script  (Steps 1–8)
 *
 * Runs on every webpage. Injects the floating analysis panel inside a
 * Shadow DOM so Sophia's styles are fully isolated from the host page.
 *
 * Step 2  (done) — selection detection + floating panel
 * Step 3  (done) — drag to move, drag corner to resize, persist state
 * Step 4  (done) — local engine: counts, density, readability, rhythm
 * Step 5  (done) — spell-check + grammar corrections popup
 * Step 6  (done) — thesaurus synonyms + click-to-focus on density words
 * Step 7  (done) — menu drawer: greeting, quote, page overview, preferences
 * Step 8  (done) — dusk mode via the .dusk class + CSS variables
 * Step 9  (next) — extract analyze() into engine/ + aiAnalyze stub
 * Step 10        — polish: keyboard focus, edge cases
 *
 * Everything runs locally. The only file read is data/quotes.json over the
 * chrome-extension:// scheme; there is no network call anywhere in here.
 */
(function () {
  'use strict';

  // Guard against double-injection (e.g. SPA soft-navigations).
  if (document.getElementById('sophia-host')) return;

  // ── Bounds for resize ───────────────────────────────────────────────────
  const MIN_W = 300, MAX_W = 680;
  const MIN_H = 160, MAX_H = 700;

  // ─────────────────────────────────────────────────────────────────────────
  //  Shadow DOM CSS
  //  Custom properties are declared on .panel so they cascade to all
  //  children within the shadow. Nothing leaks onto the host page.
  // ─────────────────────────────────────────────────────────────────────────
  const SHADOW_CSS = `
    @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;1,300;1,400&family=Hanken+Grotesk:wght@400;500;600&display=swap');

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :host { all: initial; display: block; }

    /* ── Design tokens (exact match to sophia.html) ── */
    .panel {
      --ink:          #14140f;
      --ink-soft:     #3a3a32;
      --stone-700:    #54534b;
      --stone-600:    #6b6b61;
      --stone-500:    rgba(131,129,118,.56);
      --stone-400:    #9b998e;
      --stone-300:    #c4c2b7;
      --stone-200:    #dddbd0;
      --marble:       #f6f6f5;
      --marble-bright:#ffffff;
      --sage:         #76845e;
      --sage-deep:    #5f6c4a;
      --sage-wash:    rgba(118,132,94,.10);
      --terra:        #a14b3c;
      --terra-deep:   #8a3e30;
      --terra-wash:   rgba(161,75,60,.13);
      --lapis:        #3f5d78;
      --lapis-deep:   #33495f;
      --lapis-wash:   rgba(63,93,120,.12);
      --ochre:        #b0823a;
      --ochre-deep:   #8f6829;
      --ochre-wash:   rgba(176,130,58,.16);
      --red-wash:     rgba(161,75,60,.16);
      --ease:         cubic-bezier(.22,.61,.36,1);

      /* ── Layout ── */
      display: flex;
      flex-direction: column;
      /* Positioning context for the Step 7 drawer + scrim, which are
         absolutely positioned children and must be clipped to the panel. */
      position: relative;
      width: 100%;           /* fills the host element, which holds the position */
      min-width: 300px;
      max-width: 680px;
      min-height: 160px;
      max-height: 700px;

      overflow: hidden;

      /* Hidden until .show is added */
      opacity: 0;
      pointer-events: none;
      transform: translateY(-8px) scale(.98);
      transform-origin: top left;
      /*
       * Only opacity and transform are transitioned — NOT left/top.
       * This means the show/hide animation works correctly while
       * drag position changes are instant (no sliding lag).
       */
      transition: opacity .22s var(--ease), transform .22s var(--ease);

      /* ── Surface tokens (overridden in .panel.dusk) ── */
      --panel-bg:   linear-gradient(168deg, #ffffff, #f1f1f0);
      --head-bg:    rgba(255,255,255,.68);
      --legend-bg:  rgba(255,255,255,.55);
      --shadow-a:   rgba(20,15,5,.05);
      --shadow-b:   rgba(20,15,5,.10);
      --shadow-c:   rgba(20,15,5,.17);

      /* ── Visual ── */
      font-family: "Hanken Grotesk", system-ui, sans-serif;
      font-size: 14px;
      color: var(--ink);
      -webkit-font-smoothing: antialiased;
      line-height: 1.55;
      background: var(--panel-bg);
      border: 1px solid var(--stone-200);
      border-radius: 4px;
      /* Natural shadow — ambient occlusion + warm sunlight depth */
      box-shadow:
        inset 0 1px 0 rgba(255,255,255,.9),
        0 2px 6px var(--shadow-a),
        0 10px 28px var(--shadow-b),
        0 32px 72px -16px var(--shadow-c),
        0 0 0 1px rgba(180,140,70,.05);
    }

    /* Top highlight line — matches sophia.html .panel::before */
    .panel::before {
      content: "";
      position: absolute;
      inset: 0 0 auto 0;
      height: 1px;
      z-index: 10;
      pointer-events: none;
      background: linear-gradient(90deg, transparent, rgba(255,255,255,.9), transparent);
    }

    .panel.show {
      opacity: 1;
      pointer-events: auto;
      transform: translateY(0) scale(1);
    }

    /* ── Dusk mode (dark) overrides ─────────────────────────────────────── */
    /* All colours use WCAG AA-passing values on the dusk surfaces.          */
    .panel.dusk {
      --ink:          #eceae3;
      --ink-soft:     #cbc9c0;
      --stone-700:    #cbc9c0;
      --stone-600:    #b4b2aa;
      --stone-500:    rgba(180,178,170,.52);
      --stone-400:    #a2a098;
      --stone-300:    #44474e;
      --stone-200:    #2e3038;
      --marble:       #17181b;
      --marble-bright:#1f2024;
      --sage:         #9db07f;
      --sage-deep:    #80936b;
      --sage-wash:    rgba(157,176,127,.13);
      --terra:        #c96e5c;
      --terra-deep:   #b05a49;
      --terra-wash:   rgba(201,110,92,.15);
      --lapis:        #7098b8;
      --lapis-deep:   #5a7d9e;
      --lapis-wash:   rgba(112,152,184,.15);
      --ochre:        #d4a65e;
      --ochre-deep:   #b88a48;
      --ochre-wash:   rgba(212,166,94,.18);
      --red-wash:     rgba(201,110,92,.18);

      --panel-bg:   linear-gradient(168deg, #22242b, #1a1c22);
      --head-bg:    rgba(12,13,17,.88);
      --legend-bg:  rgba(12,13,17,.72);
      --shadow-a:   rgba(4,6,18,.28);
      --shadow-b:   rgba(4,6,18,.42);
      --shadow-c:   rgba(4,6,18,.58);

      border-color: var(--stone-200);
      /* Night shadows: cool blue-black depth + moonlight inset edge */
      box-shadow:
        inset 0 1px 0 rgba(255,255,255,.055),
        0 2px 6px var(--shadow-a),
        0 12px 32px var(--shadow-b),
        0 40px 80px -24px var(--shadow-c),
        0 0 0 1px rgba(50,70,120,.2);
    }

    /* ── Header ── */
    .panel-head {
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      padding: 12px 16px 12px 10px;
      border-bottom: 1px solid var(--stone-200);
      background: var(--head-bg);
      /* grab cursor signals the draggable zone */
      cursor: grab;
      user-select: none;
      position: relative;
      z-index: 1;
    }
    .panel-head.dragging { cursor: grabbing; }

    .head-left  { display: flex; align-items: center; gap: 8px; }
    .head-right { display: flex; align-items: center; gap: 10px; }

    /* Hamburger — Step 7 will open the overview drawer */
    .menu-btn {
      appearance: none;
      border: none;
      background: transparent;
      cursor: pointer;
      width: 28px;
      height: 28px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--stone-400);
      border-radius: 3px;
      padding: 0;
      transition: color .15s, background .15s;
      flex: none;
    }
    .menu-btn:hover { color: var(--ink); background: var(--stone-200); }
    .menu-btn svg { width: 16px; height: 16px; }
    .menu-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

    .mark {
      font-family: "Cormorant Garamond", "Times New Roman", Georgia, serif;
      font-weight: 400;
      font-size: 19px;
      letter-spacing: .01em;
      color: var(--ink);
    }
    .mark b { font-weight: 500; }
    .mark-wrap { display: flex; flex-direction: column; line-height: 1; gap: 3px; }
    .mark-sub {
      font-size: 8px;
      letter-spacing: .22em;
      text-transform: uppercase;
      color: var(--stone-400);
      font-weight: 500;
    }

    /* ── Wave animation (panel header — visible while Sophia is analyzing) ── */
    .panel-wave {
      display: flex;
      align-items: center;
      gap: 2.5px;
      opacity: 0;
      pointer-events: none;
      transition: opacity .18s;
    }
    .panel-wave.active { opacity: 1; }
    .pw-bar {
      width: 2.5px;
      height: 4px;
      background: var(--sage);
      border-radius: 2px;
    }
    /* Great Wave (Kanagawa): dramatic asymmetric crest — fast rise, steep drop, long trough */
    @keyframes greek-wave-panel {
      0%, 100% { height: 3px; opacity: .28; }
      50%       { height: 18px; opacity: .92; }
    }
    .panel-wave.active .pw-bar {
      animation: greek-wave-panel 3.6s ease-in-out infinite;
    }
    .panel-wave.active .pw-bar:nth-child(1) { animation-delay: 0s; }
    .panel-wave.active .pw-bar:nth-child(2) { animation-delay: .55s; }
    .panel-wave.active .pw-bar:nth-child(3) { animation-delay: 1.1s; }
    .panel-wave.active .pw-bar:nth-child(4) { animation-delay: 1.65s; }

    .meta {
      font-size: 11px;
      letter-spacing: .14em;
      text-transform: uppercase;
      color: var(--stone-400);
    }

    .close-btn {
      appearance: none;
      border: none;
      background: transparent;
      cursor: pointer;
      font-size: 14px;
      line-height: 1;
      color: var(--stone-400);
      padding: 4px 6px;
      border-radius: 3px;
      transition: color .15s, background .15s;
    }
    .close-btn:hover { color: var(--ink); background: var(--stone-200); }
    .close-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

    /* ── Scrollable body ── */
    /*
     * flex: 1 + min-height: 0 is the standard flex trick for a scrollable
     * child: without min-height: 0, the child refuses to shrink below its
     * content height even inside a flex container with overflow: hidden.
     */
    .panel-body {
      flex: 1;
      min-height: 0;
      overflow-y: auto;
      overflow-x: hidden;
    }

    /* Thin marble-toned scrollbar */
    .panel-body::-webkit-scrollbar { width: 4px; }
    .panel-body::-webkit-scrollbar-track { background: transparent; }
    .panel-body::-webkit-scrollbar-thumb {
      background: var(--stone-300);
      border-radius: 2px;
    }

    /* ── Selection preview ── */
    .preview {
      padding: 14px 18px;
      border-bottom: 1px solid var(--stone-200);
    }
    .preview-label {
      font-size: 10px;
      letter-spacing: .16em;
      text-transform: uppercase;
      color: var(--stone-400);
      margin-bottom: 8px;
    }
    .preview-text {
      font-family: "Cormorant Garamond", "Times New Roman", Georgia, serif;
      font-size: 17px;
      line-height: 1.5;
      color: var(--ink-soft);
      display: -webkit-box;
      -webkit-line-clamp: 2;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }

    /* ── Bar: live count + Refine button ── */
    .bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 18px;
    }
    .live-count { font-size: 12px; color: var(--stone-600); }
    .live-count b { color: var(--ink); font-weight: 600; }

    .refine-btn {
      appearance: none;
      border: none;
      cursor: pointer;
      font-family: "Hanken Grotesk", system-ui, sans-serif;
      font-weight: 600;
      font-size: 13px;
      letter-spacing: .04em;
      color: var(--marble-bright);
      background: var(--sage);
      padding: 9px 20px;
      border-radius: 2px;
      transition: background .2s var(--ease), transform .15s var(--ease);
    }
    .refine-btn:hover         { background: var(--sage-deep); }
    .refine-btn:active        { transform: translateY(1px); }
    .refine-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 3px; }

    /* ── Color legend ── */
    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      padding: 10px 18px;
      border-top: 1px solid var(--stone-200);
      background: var(--legend-bg);
    }
    .key {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 10px;
      letter-spacing: .12em;
      text-transform: uppercase;
      color: var(--stone-600);
    }
    .key i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; flex: none; }
    .k-terra { background: var(--terra); }
    .k-lapis { background: var(--lapis); }
    .k-sage  { background: var(--sage);  }
    .k-ochre { background: var(--ochre); }

    /* ── Results sections (I–IV) ── */
    .results {
      border-top: 1px solid var(--stone-200);
      max-height: 0;
      overflow: hidden;
      opacity: 0;
      transition: max-height .5s var(--ease), opacity .35s var(--ease);
    }
    .results.show { max-height: 2000px; opacity: 1; }

    .block { padding: 18px; border-bottom: 1px solid var(--stone-200); }
    .block:last-child { border-bottom: none; }

    .block h3 {
      font-weight: 600;
      font-size: 10px;
      letter-spacing: .2em;
      text-transform: uppercase;
      color: var(--stone-600);
      margin-bottom: 12px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .block h3 .n {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-weight: 500;
      font-size: 14px;
      letter-spacing: 0;
      text-transform: none;
      color: var(--stone-400);
      min-width: 16px;
    }

    .placeholder { font-size: 13px; color: var(--stone-400); font-style: italic; }
    .empty       { font-size: 13px; color: var(--stone-400); }
    .empty.ok    { color: var(--sage-deep); }

    /* ── Resize handle ── */
    /*
     * position: absolute inside position: fixed creates a containing block
     * relationship, so bottom:0; right:0 anchors it to the panel's corner.
     * It sits above .panel-body (z-index: 2) so it's always clickable.
     */
    .resize-handle {
      position: absolute;
      bottom: 0;
      right: 0;
      width: 18px;
      height: 18px;
      cursor: nwse-resize;
      z-index: 2;
      opacity: 0.45;
      transition: opacity .2s;
      /* 6-dot triangular grip — classic resize indicator */
      background-image:
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px),
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px),
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px),
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px),
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px),
        radial-gradient(circle, var(--stone-400) 1.5px, transparent 1.5px);
      background-position:
        13px 13px, 9px 13px, 13px 9px,
        5px 13px,  9px 9px,  13px 5px;
      background-repeat: no-repeat;
    }
    .resize-handle:hover { opacity: 1; }

    /* ── Analysis result elements ─────────────────────────────────── */

    /* Corrections */
    .correction-item {
      display: flex; align-items: flex-start; gap: 10px;
      padding: 8px 0; border-bottom: 1px solid var(--stone-200);
      font-size: 12.5px; line-height: 1.45;
    }
    .correction-item:last-child { border-bottom: none; }
    .c-dot { width: 7px; height: 7px; border-radius: 50%; flex: none; margin-top: 4px; }
    .c-spell  .c-dot  { background: var(--terra); }
    .c-grammar .c-dot { background: var(--lapis); }
    .c-text { color: var(--ink-soft); }

    /* Synonyms */
    .synonym-row {
      display: flex; align-items: center; flex-wrap: wrap; gap: 6px;
      padding: 7px 0; border-bottom: 1px solid var(--stone-200); font-size: 12.5px;
    }
    .synonym-row:last-child { border-bottom: none; }
    .syn-word { font-weight: 600; color: var(--ink); min-width: 64px; }
    .syn-arrow { color: var(--stone-300); }
    .syn-chip {
      background: var(--sage-wash); color: var(--sage-deep);
      border: 1px solid rgba(118,132,94,.2); border-radius: 3px;
      padding: 2px 8px; font-size: 11px; font-weight: 500; cursor: pointer;
      transition: background .15s, color .15s;
    }
    .syn-chip:hover { background: var(--sage); color: #fff; }

    /* Density rank */
    .rank-row {
      display: grid; grid-template-columns: 88px 1fr 34px 68px;
      align-items: center; gap: 8px; padding: 7px 0;
      border-bottom: 1px solid var(--stone-200); font-size: 12px;
    }
    .rank-row:last-child { border-bottom: none; }
    .rank-word { font-weight: 600; color: var(--ink); }
    .rank-bar-wrap { height: 4px; background: var(--stone-200); border-radius: 2px; overflow: hidden; }
    .rank-bar { height: 100%; border-radius: 2px; background: var(--stone-400); }
    .rank-dense .rank-bar { background: var(--terra); }
    .rank-heavy .rank-bar { background: var(--ochre); }
    .rank-count { text-align: right; color: var(--stone-600); }
    .rank-tag {
      font-size: 9px; letter-spacing: .08em; text-transform: uppercase;
      font-weight: 600; padding: 2px 5px; border-radius: 2px;
    }
    .rank-tag.dense { background: var(--terra-wash); color: var(--terra); }
    .rank-tag.heavy { background: var(--ochre-wash); color: var(--ochre); }

    /* Counts grid */
    .metrics-grid {
      display: grid; grid-template-columns: repeat(4, 1fr);
      gap: 1px; background: var(--stone-200);
      border: 1px solid var(--stone-200); border-radius: 4px;
      overflow: hidden; margin-bottom: 14px;
    }
    .metric {
      background: var(--marble-bright); padding: 12px 4px;
      display: flex; flex-direction: column; align-items: center; gap: 3px;
    }
    .metric-val {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-size: 22px; font-weight: 400; color: var(--ink); line-height: 1;
    }
    .metric-lab {
      font-size: 9px; letter-spacing: .14em; text-transform: uppercase;
      color: var(--stone-400); font-weight: 600;
    }

    /* Inline stat rows (readability, tone, humanness) */
    .stat-row {
      display: flex; align-items: flex-start; justify-content: space-between;
      gap: 10px; padding: 9px 0; border-top: 1px solid var(--stone-200); font-size: 12.5px;
    }
    .stat-label {
      font-size: 9.5px; letter-spacing: .16em; text-transform: uppercase;
      color: var(--stone-400); font-weight: 600; padding-top: 3px; white-space: nowrap;
    }
    .stat-val { color: var(--ink-soft); text-align: right; line-height: 1.45; }
    .stat-val b { color: var(--ink); font-weight: 600; }

    /* Humanness bar */
    .humanness-wrap { display: flex; flex-direction: column; gap: 6px; flex: 1; }
    .humanness-bar-bg { height: 5px; background: var(--stone-200); border-radius: 3px; overflow: hidden; }
    .humanness-bar    { height: 100%; border-radius: 3px; transition: width .7s var(--ease); }
    .humanness-score  { font-size: 11.5px; font-weight: 600; }

    /* ══════════════════════════════════════════════════════════════════
       Step 7 — Overview drawer
       Slides in from the left, over the panel body. The scrim sits
       between the drawer and the body so a click outside dismisses it.
       Both live INSIDE .panel so they inherit every design token and
       are clipped by the panel's own border-radius / overflow.
       ══════════════════════════════════════════════════════════════════ */
    .scrim {
      position: absolute; inset: 0; z-index: 40;
      background: rgba(20,20,15,.28);
      backdrop-filter: blur(1.5px);
      opacity: 0; pointer-events: none;
      transition: opacity .24s var(--ease);
    }
    .scrim.show { opacity: 1; pointer-events: auto; }

    .drawer {
      position: absolute; top: 0; bottom: 0; left: 0; z-index: 41;
      width: min(90%, 340px);
      display: flex; flex-direction: column;
      background: var(--panel-bg);
      border-right: 1px solid var(--stone-200);
      box-shadow: 6px 0 28px -8px rgba(20,15,5,.28);
      transform: translateX(-102%);
      transition: transform .28s var(--ease);
      overflow: hidden;
    }
    .drawer.show { transform: translateX(0); }
    /* .drawer{display:flex} outranks the UA [hidden] rule, so state it
       explicitly — otherwise a closed drawer stays in the tab order. */
    .drawer[hidden] { display: none; }

    /* The shaft of light — the signature element, recomputed to the
       drawer's own box so it stays balanced at any panel size. */
    .drawer::before {
      content: ""; position: absolute; top: 0; bottom: 0; left: 18%;
      width: 46%; pointer-events: none;
      background: linear-gradient(102deg,
        transparent 0%, rgba(255,252,240,.55) 42%, rgba(255,250,235,.22) 70%, transparent 100%);
      mix-blend-mode: normal;
    }

    .drawer-head {
      position: relative; z-index: 1;
      display: flex; align-items: flex-start; justify-content: space-between;
      gap: 10px; padding: 14px 16px 12px;
      border-bottom: 1px solid var(--stone-200);
      background: var(--head-bg);
    }
    .drawer-close {
      flex: none; background: none; border: none; cursor: pointer;
      font-size: 13px; line-height: 1; color: var(--stone-400);
      padding: 4px 5px; border-radius: 3px; font-family: inherit;
      transition: color .15s var(--ease), background .15s var(--ease);
    }
    .drawer-close:hover { color: var(--ink); background: var(--stone-200); }
    .drawer-close:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

    .greeting {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-weight: 300; font-size: 22px; line-height: 1.2;
      color: var(--ink); letter-spacing: .005em;
    }
    .greeting b { font-weight: 500; }

    .quote {
      position: relative; z-index: 1;
      padding: 13px 16px 15px;
      border-bottom: 1px solid var(--stone-200);
    }
    .quote-text {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-style: italic; font-weight: 300;
      font-size: 15.5px; line-height: 1.45; color: var(--ink-soft);
    }
    .quote-src {
      margin-top: 7px; font-size: 9.5px; font-weight: 600;
      letter-spacing: .16em; text-transform: uppercase; color: var(--stone-400);
    }

    .drawer-body {
      position: relative; z-index: 1;
      flex: 1; overflow-y: auto; overscroll-behavior: contain;
      padding: 4px 0 16px;
    }
    .drawer-body::-webkit-scrollbar { width: 7px; }
    .drawer-body::-webkit-scrollbar-thumb {
      background: var(--stone-300); border-radius: 4px;
    }

    .dsection { padding: 13px 16px 4px; }
    .dsection + .dsection { border-top: 1px solid var(--stone-200); margin-top: 6px; }
    .dsection h4 {
      font-size: 9.5px; font-weight: 600; letter-spacing: .16em;
      text-transform: uppercase; color: var(--stone-400);
      margin-bottom: 10px; display: flex; align-items: center; gap: 7px;
    }
    .dsection h4::after {
      content: ""; flex: 1; height: 1px; background: var(--stone-200);
    }

    /* Page overview stat grid */
    .ov-grid {
      display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 11px;
    }
    .ov-cell {
      background: var(--marble-bright); border: 1px solid var(--stone-200);
      border-radius: 3px; padding: 8px 9px;
    }
    .ov-num {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-size: 21px; font-weight: 400; line-height: 1.05; color: var(--ink);
    }
    .ov-num small { font-size: 11px; color: var(--stone-600); font-family: inherit; }
    .ov-cap {
      margin-top: 3px; font-size: 9px; font-weight: 600; letter-spacing: .13em;
      text-transform: uppercase; color: var(--stone-400);
    }
    .ov-cell.flag .ov-num { color: var(--terra); }
    .ov-cell.warn .ov-num { color: var(--ochre); }

    /* Page-wide density chips */
    .ov-words { display: flex; flex-wrap: wrap; gap: 5px; }
    .ov-chip {
      display: inline-flex; align-items: baseline; gap: 5px;
      padding: 3px 8px; border-radius: 2px; font-size: 11.5px;
      background: var(--stone-200); color: var(--ink-soft);
      border: 1px solid transparent;
    }
    .ov-chip b { font-weight: 600; }
    .ov-chip .c { font-size: 9.5px; font-weight: 600; color: var(--stone-600); }
    .ov-chip.heavy { background: var(--ochre-wash); border-color: rgba(176,130,58,.3); }
    .ov-chip.heavy .c { color: var(--ochre-deep); }
    .ov-chip.dense { background: var(--terra-wash); border-color: rgba(161,75,60,.3); }
    .ov-chip.dense .c { color: var(--terra-deep); }

    .ov-empty { font-size: 12px; color: var(--stone-400); font-style: italic; }

    .ov-refresh {
      margin-top: 10px; background: none; border: 1px solid var(--stone-300);
      border-radius: 3px; padding: 5px 11px; cursor: pointer;
      font-family: inherit; font-size: 10.5px; font-weight: 600;
      letter-spacing: .1em; text-transform: uppercase; color: var(--stone-600);
      transition: border-color .15s var(--ease), color .15s var(--ease);
    }
    .ov-refresh:hover { border-color: var(--sage); color: var(--sage-deep); }
    .ov-refresh:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

    /* Preferences */
    .pref-row {
      display: flex; align-items: center; justify-content: space-between;
      gap: 10px; padding: 7px 0; font-size: 12.5px; color: var(--ink-soft);
    }
    .pref-row + .pref-row { border-top: 1px solid rgba(196,194,183,.4); }
    .pref-row.off { opacity: .45; }
    .pref-label { display: flex; flex-direction: column; gap: 1px; }
    .pref-hint { font-size: 10px; color: var(--stone-400); }

    .name-input {
      width: 100%; font-family: inherit; font-size: 12.5px; color: var(--ink);
      background: var(--marble-bright); border: 1px solid var(--stone-300);
      border-radius: 3px; padding: 6px 9px; margin-bottom: 4px;
    }
    .name-input:focus { outline: none; border-color: var(--sage); }
    .name-input::placeholder { color: var(--stone-400); }

    /* Segmented theme control */
    .seg { display: flex; border: 1px solid var(--stone-300); border-radius: 3px; overflow: hidden; }
    .seg button {
      background: none; border: none; cursor: pointer; font-family: inherit;
      font-size: 10.5px; font-weight: 600; letter-spacing: .06em;
      padding: 5px 10px; color: var(--stone-600);
      transition: background .15s var(--ease), color .15s var(--ease);
    }
    .seg button + button { border-left: 1px solid var(--stone-300); }
    .seg button:hover { background: var(--stone-200); }
    .seg button.on { background: var(--sage); color: #fff; }
    .seg button:focus-visible { outline: 2px solid var(--ink); outline-offset: -2px; }

    /* Switch */
    .sw {
      flex: none; width: 34px; height: 19px; border-radius: 10px; border: none;
      background: var(--stone-300); cursor: pointer; position: relative;
      padding: 0; transition: background .2s var(--ease);
    }
    .sw::after {
      content: ""; position: absolute; top: 2px; left: 2px;
      width: 15px; height: 15px; border-radius: 50%; background: #fff;
      box-shadow: 0 1px 3px rgba(20,15,5,.3);
      transition: transform .2s var(--ease);
    }
    .sw.on { background: var(--sage); }
    .sw.on::after { transform: translateX(15px); }
    .sw:disabled { cursor: not-allowed; }
    .sw:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

    /* ── Dusk overrides for the drawer ── */
    .panel.dusk .drawer::before {
      background: linear-gradient(102deg,
        transparent 0%, rgba(255,244,214,.10) 42%, rgba(255,244,214,.04) 70%, transparent 100%);
    }
    .panel.dusk .scrim { background: rgba(0,0,0,.45); }
    .panel.dusk .ov-chip { background: rgba(255,255,255,.06); }
    .panel.dusk .name-input,
    .panel.dusk .ov-cell { background: var(--marble-bright); }
  `;

  // ─────────────────────────────────────────────────────────────────────────
  //  Panel markup
  //  .panel-body wraps everything below the header so it can scroll as a
  //  unit when the user has resized the panel shorter than its content.
  //  The resize handle sits outside .panel-body so it never scrolls away.
  // ─────────────────────────────────────────────────────────────────────────
  const PANEL_HTML = `
    <div class="panel" id="sophia-panel" role="dialog" aria-label="Sophia — writing companion">

      <div class="panel-head" id="sophia-head">
        <div class="head-left">
          <!-- Step 7: clicking this opens the overview drawer -->
          <button class="menu-btn" id="sophia-menu" aria-label="Open menu" aria-haspopup="true">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round">
              <line x1="3" y1="6"  x2="17" y2="6"/>
              <line x1="3" y1="10" x2="17" y2="10"/>
              <line x1="3" y1="14" x2="17" y2="14"/>
            </svg>
          </button>
          <div class="mark-wrap">
            <div class="mark">Soph<b>ia</b></div>
            <div class="mark-sub">Intelligent Assistant</div>
          </div>
        </div>
        <div class="head-right">
          <div class="panel-wave" id="sophia-wave" aria-hidden="true">
            <span class="pw-bar"></span>
            <span class="pw-bar"></span>
            <span class="pw-bar"></span>
            <span class="pw-bar"></span>
          </div>
          <button class="close-btn" id="sophia-close" aria-label="Close Sophia">✕</button>
        </div>
      </div>

      <div class="panel-body" id="sophia-body">

        <div class="preview">
          <div class="preview-label">Selected text</div>
          <div class="preview-text" id="sophia-preview"></div>
        </div>

        <div class="bar">
          <div class="live-count" id="sophia-count"></div>
          <button class="refine-btn" id="sophia-refine">Refine</button>
        </div>

        <div class="legend">
          <span class="key"><i class="k-terra"></i> Spelling</span>
          <span class="key"><i class="k-lapis"></i> Grammar</span>
          <span class="key"><i class="k-sage"></i> Word choice</span>
          <span class="key"><i class="k-ochre"></i> Density</span>
        </div>

        <div class="results" id="sophia-results" aria-live="polite">
          <div class="block">
            <h3><span class="n">I</span> Corrections</h3>
            <div id="sophia-fixes">
              <p class="placeholder">I've read your selection. Hit Refine and I'll take a proper look.</p>
            </div>
          </div>
          <div class="block">
            <h3><span class="n">II</span> Word choice</h3>
            <div id="sophia-reps">
              <p class="placeholder">Better words, waiting in the wings.</p>
            </div>
          </div>
          <div class="block">
            <h3><span class="n">III</span> Word density · ranked</h3>
            <div id="sophia-rank">
              <p class="placeholder">Your most-used words, ranked and exposed.</p>
            </div>
          </div>
          <div class="block">
            <h3><span class="n">IV</span> Counts</h3>
            <div id="sophia-metrics">
              <p class="placeholder">The numbers — plain, simple, honest.</p>
            </div>
          </div>
        </div>

      </div><!-- /.panel-body -->

      <!-- ── Step 7: overview drawer ──────────────────────────────────
           Sits inside .panel so it inherits the design tokens, is clipped
           by the panel's overflow, and moves/resizes with it for free. -->
      <div class="scrim" id="sophia-scrim"></div>

      <aside class="drawer" id="sophia-drawer" role="dialog"
             aria-label="Sophia overview" aria-modal="false" hidden>

        <div class="drawer-head">
          <div class="greeting" id="sophia-greeting">Hello.</div>
          <button class="drawer-close" id="sophia-drawer-close"
                  aria-label="Close menu">✕</button>
        </div>

        <div class="quote">
          <div class="quote-text" id="sophia-quote-text"></div>
          <div class="quote-src"  id="sophia-quote-src"></div>
        </div>

        <div class="drawer-body">

          <div class="dsection">
            <h4>This page</h4>
            <div class="ov-grid" id="sophia-ov-grid"></div>
            <div class="ov-words" id="sophia-ov-words"></div>
            <button class="ov-refresh" id="sophia-ov-refresh">Rescan page</button>
          </div>

          <div class="dsection">
            <h4>Appearance</h4>
            <div class="pref-row">
              <span class="pref-label">Theme</span>
              <div class="seg" role="group" aria-label="Theme">
                <button id="sophia-theme-system" data-theme="system">System</button>
                <button id="sophia-theme-dawn" data-theme="dawn">Dawn</button>
                <button id="sophia-theme-dusk" data-theme="dusk">Dusk</button>
              </div>
            </div>
          </div>

          <div class="dsection">
            <h4>Your name</h4>
            <input class="name-input" id="sophia-name" type="text"
                   placeholder="What should I call you?" autocomplete="off"
                   spellcheck="false" maxlength="40">
          </div>

          <div class="dsection">
            <h4>Checks</h4>
            <div class="pref-row">
              <span class="pref-label">Spelling</span>
              <button class="sw" id="sophia-t-spelling" role="switch"></button>
            </div>
            <div class="pref-row">
              <span class="pref-label">Grammar</span>
              <button class="sw" id="sophia-t-grammar" role="switch"></button>
            </div>
            <div class="pref-row">
              <span class="pref-label">Word density</span>
              <button class="sw" id="sophia-t-density" role="switch"></button>
            </div>
            <div class="pref-row">
              <span class="pref-label">Readability</span>
              <button class="sw" id="sophia-t-readability" role="switch"></button>
            </div>
            <div class="pref-row">
              <span class="pref-label">Sophia orb</span>
              <button class="sw" id="sophia-t-bubble" role="switch"></button>
            </div>
            <div class="pref-row off">
              <span class="pref-label">
                Smarter AI suggestions
                <span class="pref-hint">Coming later</span>
              </span>
              <button class="sw" id="sophia-t-ai" role="switch" disabled
                      aria-disabled="true" title="Not available in this version"></button>
            </div>
          </div>

        </div>
      </aside>

      <!-- Corner grip: drag to resize -->
      <div class="resize-handle" id="sophia-resize" aria-hidden="true"></div>

    </div>
  `;

  // ─────────────────────────────────────────────────────────────────────────
  //  Sophia Bubble — persistent orb that lives on every page
  //  Has its own Shadow DOM so it is fully isolated from the panel and page.
  // ─────────────────────────────────────────────────────────────────────────
  const BUBBLE_CSS = `
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :host { display: block; }

    .bubble-btn {
      width: 52px;
      height: 52px;
      border-radius: 50%;
      border: none;
      cursor: pointer;
      background: linear-gradient(145deg, #7b8f62, #596a43);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow:
        0 4px 18px rgba(89,106,67,.5),
        0 1px 4px  rgba(20,20,15,.22),
        inset 0 1px 0 rgba(255,255,255,.18);
      transition: transform .2s cubic-bezier(.22,.61,.36,1),
                  box-shadow .2s cubic-bezier(.22,.61,.36,1);
      -webkit-font-smoothing: antialiased;
      position: relative;
    }
    .bubble-btn:hover {
      transform: scale(1.1);
      box-shadow:
        0 7px 28px rgba(89,106,67,.62),
        0 2px 8px  rgba(20,20,15,.24),
        inset 0 1px 0 rgba(255,255,255,.22);
    }
    .bubble-btn:active { transform: scale(.93); transition-duration: .08s; }

    @keyframes aegean-breathe {
      0%, 100% {
        box-shadow: 0 3px 14px rgba(89,106,67,.42), 0 1px 3px rgba(20,20,15,.18),
                    inset 0 1px 0 rgba(255,255,255,.18);
      }
      50% {
        box-shadow: 0 5px 24px rgba(89,106,67,.58), 0 1px 6px rgba(20,20,15,.2),
                    inset 0 1px 0 rgba(255,255,255,.22),
                    0 0 10px 3px rgba(170,160,110,.10);
      }
    }
    @keyframes aegean-ripple {
      0%   { transform: scale(1);   opacity: .2; }
      100% { transform: scale(1.55); opacity: 0; }
    }
    .bubble-btn { animation: aegean-breathe 4.2s ease-in-out infinite; }
    .bubble-btn::before {
      content: '';
      position: absolute;
      inset: -5px;
      border-radius: 50%;
      border: 1.5px solid rgba(118,160,120,.3);
      pointer-events: none;
      animation: aegean-ripple 4.2s ease-out infinite;
    }
    .bubble-btn::after {
      content: '';
      position: absolute;
      inset: -5px;
      border-radius: 50%;
      border: 1px solid rgba(118,160,120,.15);
      pointer-events: none;
      animation: aegean-ripple 4.2s ease-out 2.1s infinite;
    }

    .bubble-letter {
      font-family: "Cormorant Garamond", Georgia, serif;
      font-size: 26px;
      font-weight: 400;
      color: rgba(255,255,255,.96);
      line-height: 1;
      user-select: none;
      transition: opacity .15s;
    }

    .wave {
      position: absolute;
      display: flex;
      align-items: center;
      gap: 3px;
      opacity: 0;
      transition: opacity .15s;
    }
    .bubble-btn.working .wave         { opacity: 1; }
    .bubble-btn.working .bubble-letter { opacity: 0; }

    .wave-bar {
      width: 3px;
      background: rgba(255,255,255,.92);
      border-radius: 3px;
      height: 5px;
    }
    @keyframes greek-wave-bubble {
      0%, 100% { height: 3px; opacity: .35; }
      50%       { height: 22px; opacity: 1; }
    }
    .bubble-btn.working .wave-bar {
      animation: greek-wave-bubble 3.2s ease-in-out infinite;
    }
    /* Crest travels left → right, one bar at a time */
    .wave-bar:nth-child(1) { animation-delay: 0s; }
    .wave-bar:nth-child(2) { animation-delay: .6s; }
    .wave-bar:nth-child(3) { animation-delay: 1.2s; }
    .wave-bar:nth-child(4) { animation-delay: 1.8s; }
    .wave-bar:nth-child(5) { animation-delay: 2.4s; }

    .bubble-tip {
      position: absolute;
      right: calc(100% + 10px);
      top: 50%;
      transform: translateY(-50%) translateX(6px);
      white-space: nowrap;
      background: #14140f;
      color: #f6f6f5;
      font-family: system-ui, -apple-system, sans-serif;
      font-size: 11.5px;
      font-weight: 500;
      padding: 5px 11px;
      border-radius: 4px;
      opacity: 0;
      pointer-events: none;
      transition: opacity .18s, transform .18s;
      letter-spacing: .01em;
    }
    .bubble-tip::after {
      content: '';
      position: absolute;
      left: 100%;
      top: 50%;
      transform: translateY(-50%);
      border: 4px solid transparent;
      border-left-color: #14140f;
    }
    .bubble-btn:hover .bubble-tip {
      opacity: 1;
      transform: translateY(-50%) translateX(0);
    }
  `;

  const BUBBLE_HTML = `
    <button class="bubble-btn" id="sophia-bubble" aria-label="Open Sophia">
      <span class="bubble-letter">S</span>
      <span class="wave" aria-hidden="true">
        <span class="wave-bar"></span>
        <span class="wave-bar"></span>
        <span class="wave-bar"></span>
        <span class="wave-bar"></span>
        <span class="wave-bar"></span>
      </span>
      <span class="bubble-tip">I'm right here</span>
    </button>
  `;

  // ─────────────────────────────────────────────────────────────────────────
  //  Shadow DOM setup
  //  The host sits at (0,0) with zero size and overflow: visible so the
  //  fixed-positioned panel can appear anywhere without scrolling the page.
  //  Appending to <html> (not <body>) survives body replacements in SPAs.
  // ─────────────────────────────────────────────────────────────────────────
  const host = document.createElement('div');
  host.id = 'sophia-host';
  // The host IS the positioned container we move during drag.
  // width matches the default panel width; height is auto (content-driven).
  // Start off-screen so the opacity-0 panel never flashes at (0,0).
  Object.assign(host.style, {
    position: 'fixed', top: '-9999px', left: '-9999px',
    width: '380px',
    zIndex: '2147483647', pointerEvents: 'none',
  });
  document.documentElement.appendChild(host);

  const shadow = host.attachShadow({ mode: 'open' });
  const styleEl = document.createElement('style');
  styleEl.textContent = SHADOW_CSS;
  const wrapper = document.createElement('div');
  wrapper.innerHTML = PANEL_HTML;
  shadow.appendChild(styleEl);
  shadow.appendChild(wrapper);

  // ── Bubble shadow DOM ─────────────────────────────────────────────────
  const bubbleHost = document.createElement('div');
  bubbleHost.id = 'sophia-bubble-host';
  Object.assign(bubbleHost.style, {
    position: 'fixed',
    top:      (window.innerHeight - 76) + 'px',
    left:     (window.innerWidth  - 76) + 'px',
    width:    '52px',
    height:   '52px',
    zIndex:   '2147483646',
    display:  'block',
    cursor:   'grab',
    userSelect: 'none',
  });
  document.documentElement.appendChild(bubbleHost);

  const bubbleShadow  = bubbleHost.attachShadow({ mode: 'open' });
  const bubbleStyleEl = document.createElement('style');
  bubbleStyleEl.textContent = BUBBLE_CSS;
  const bubbleWrapper = document.createElement('div');
  bubbleWrapper.innerHTML = BUBBLE_HTML;
  bubbleShadow.appendChild(bubbleStyleEl);
  bubbleShadow.appendChild(bubbleWrapper);

  // ── Element references ────────────────────────────────────────────────
  const panel        = shadow.getElementById('sophia-panel');
  const panelHead    = shadow.getElementById('sophia-head');
  const menuBtn      = shadow.getElementById('sophia-menu');
  const closeBtn     = shadow.getElementById('sophia-close');
  const refineBtn    = shadow.getElementById('sophia-refine');
  const previewEl    = shadow.getElementById('sophia-preview');
  const countEl      = shadow.getElementById('sophia-count');
  const resultsEl    = shadow.getElementById('sophia-results');
  const resizeHandle = shadow.getElementById('sophia-resize');
  const waveEl       = shadow.getElementById('sophia-wave');
  const bubbleBtn    = bubbleShadow.getElementById('sophia-bubble');
  const bubbleTip    = bubbleShadow.querySelector('.bubble-tip');

  // ── Quip rotation (Jarvis/Friday personality) ─────────────────────────
  const BUBBLE_QUIPS = [
    "I'm right here.",
    "Ready when you are.",
    "Got something to refine?",
    "Your words, elevated.",
    "Say the word.",
    "Standing by.",
    "Watching over your prose.",
    "At your service.",
    "What are we working on?",
    "Awaiting your command.",
    "The page is yours.",
    "Shall we begin?",
  ];
  let quipIdx = Math.floor(Math.random() * BUBBLE_QUIPS.length);
  setInterval(() => {
    quipIdx = (quipIdx + 1) % BUBBLE_QUIPS.length;
    if (bubbleTip) bubbleTip.textContent = BUBBLE_QUIPS[quipIdx];
  }, 4500);

  // ── State ─────────────────────────────────────────────────────────────
  let currentText    = '';
  let currentElement = null;
  let panelVisible   = false;
  let userResized    = false;
  let lastAnalysis   = null;

  // Drag-to-move state
  let dragging = false;
  let drOffX   = 0;  // cursor offset from host left edge at drag start
  let drOffY   = 0;  // cursor offset from host top  edge at drag start

  // Drag-to-resize state
  let resizing = false;
  let rsStartX = 0;
  let rsStartY = 0;
  let rsStartW = 0;
  let rsStartH = 0;

  // Bubble drag state
  let bdDragging = false;
  let bdOffX = 0, bdOffY = 0;
  let bdStartX = 0, bdStartY = 0;
  let bdWasDragged = false;

  // ── Helpers ───────────────────────────────────────────────────────────

  function isEditable(el) {
    if (!el) return false;
    const tag = el.tagName;
    if (tag === 'TEXTAREA') return true;
    if (tag === 'INPUT') {
      const t = (el.type || 'text').toLowerCase();
      return /^(text|search|email|url|password|number)$/.test(t);
    }
    return el.isContentEditable === true;
  }

  /*
   * textarea / input: the Selection API doesn't apply to these elements.
   * They track selection through their own selectionStart / selectionEnd.
   * contenteditable: use the real window.getSelection().
   */
  function getSelectedText(el) {
    if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
      return el.value.slice(el.selectionStart, el.selectionEnd);
    }
    return (window.getSelection() || '').toString();
  }

  function quickCount(text) {
    const t = text.trim();
    return {
      words:     t ? t.split(/\s+/).length : 0,
      sentences: (t.match(/[^.!?]+[.!?]+/g) || (t ? [t] : [])).length,
    };
  }

  /*
   * Clamp a proposed top-left so the panel stays within the viewport.
   * We keep at least 60px of panel visible at the bottom so the header
   * (and therefore the drag handle) is always reachable.
   */
  function clamp(left, top, panelW) {
    return {
      left: Math.max(0, Math.min(left, window.innerWidth  - panelW)),
      top:  Math.max(0, Math.min(top,  window.innerHeight - 60)),
    };
  }

  // ── Persistence ───────────────────────────────────────────────────────

  function saveState() {
    const rect = host.getBoundingClientRect();
    chrome.storage.local.set({
      'sophia-panel-state': {
        top:    Math.round(rect.top),
        left:   Math.round(rect.left),
        width:  host.offsetWidth,
        height: userResized ? panel.offsetHeight : null,
      },
    });
  }

  // ── Positioning ───────────────────────────────────────────────────────

  /*
   * Place the panel near the mouse cursor with viewport-edge flipping.
   * Used only when there is no saved state.
   */
  function positionFresh(mouseX, mouseY) {
    const PW = host.offsetWidth || 380;
    const PH = 240;
    const margin = 14;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    let left = mouseX + margin;
    let top  = mouseY + margin;

    if (left + PW > vw - margin) left = mouseX - PW - margin;
    if (left < margin) left = margin;
    if (top  + PH > vh - margin) top  = mouseY - PH - margin;
    if (top  < margin) top = margin;

    host.style.left  = left + 'px';
    host.style.top   = top  + 'px';
    panel.style.transformOrigin = (left > mouseX ? 'top left' : 'top right');
  }

  // ── Show / hide ───────────────────────────────────────────────────────

  function showPanel(mouseX, mouseY, text, el) {
    currentText    = text    || currentText    || '';
    currentElement = el      || currentElement || null;
    panelVisible   = true;

    previewEl.textContent = currentText || '';
    if (currentText) {
      const { words, sentences } = quickCount(currentText);
      countEl.innerHTML =
        '<b>' + words + '</b> word' + (words === 1 ? '' : 's') +
        ' · <b>' + sentences + '</b> sentence' + (sentences === 1 ? '' : 's');
    } else {
      countEl.innerHTML = 'Select text on this page to begin.';
    }

    /*
     * Load the saved position + size before showing.
     * chrome.storage.local responds in microseconds (local), so there is
     * no visible delay. The panel starts at opacity: 0 and only fades in
     * after position is set — no flash at position (0,0).
     */
    chrome.storage.local.get('sophia-panel-state', (data) => {
      const s = data['sophia-panel-state'];
      if (s && s.left != null) {
        const { left, top } = clamp(s.left, s.top, s.width || 380);
        host.style.left  = left + 'px';
        host.style.top   = top  + 'px';
        if (s.width)  host.style.width   = s.width  + 'px';
        if (s.height) { panel.style.height = s.height + 'px'; userResized = true; }
      } else {
        positionFresh(mouseX, mouseY);
      }
      host.style.pointerEvents = 'auto';
      panel.classList.add('show');
    });
  }

  function hidePanel() {
    if (!panelVisible) return;
    panelVisible = false;
    closeDrawer(false);          // never reopen the panel with a stale drawer
    panel.classList.remove('show');
    host.style.pointerEvents = 'none';
    resultsEl.classList.remove('show');
    removeHighlights(currentElement);
    hideInlineTip();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Local analysis engine
  // ══════════════════════════════════════════════════════════════════════

  const STOP = new Set(['a','an','the','and','but','or','nor','for','yet','so',
    'in','on','at','to','by','of','up','as','is','it','be','was','are','were',
    'has','had','have','do','did','does','will','would','could','should','may',
    'might','shall','that','this','these','those','i','me','my','we','our',
    'you','your','he','him','his','she','her','they','them','their','with',
    'from','into','than','more','been','just','not','no','if','its',"it's",
    'can','all','which','what','who','when','where','how','there','here',
    'then','about','also','over','out','after','before','between','such']);

  const THESAURUS = {
    'good':['excellent','fine','solid','strong'], 'great':['remarkable','impressive','superb'],
    'bad':['poor','weak','flawed','inadequate'], 'big':['large','substantial','significant'],
    'small':['modest','minimal','limited'], 'very':['quite','highly','particularly'],
    'really':['truly','genuinely','indeed'], 'make':['create','build','craft','produce'],
    'get':['obtain','acquire','gain'], 'use':['employ','apply','leverage'],
    'show':['demonstrate','reveal','illustrate'], 'think':['believe','consider','regard'],
    'need':['require','demand','necessitate'], 'important':['crucial','vital','essential'],
    'change':['alter','modify','transform'], 'help':['assist','support','enable'],
    'look':['appear','examine','inspect'], 'work':['function','operate','execute'],
    'things':['elements','aspects','factors'], 'thing':['item','aspect','detail'],
    'way':['method','approach','technique'], 'people':['individuals','users','members'],
    'just':['simply','merely','precisely'], 'new':['novel','fresh','innovative'],
    'different':['distinct','varied','diverse'], 'know':['understand','recognize','grasp'],
    'want':['desire','seek','prefer'], 'problem':['issue','challenge','concern'],
    'like':['such as','similar to','comparable to'],
  };

  const TONE_POS  = new Set(['excellent','amazing','great','wonderful','fantastic','brilliant',
    'outstanding','perfect','love','best','happy','positive','success','beautiful',
    'helpful','exciting','joy','glad','pleased','effective','strong','achieve','improve']);
  const TONE_NEG  = new Set(['terrible','awful','horrible','bad','worst','hate','fail',
    'poor','wrong','difficult','problem','unfortunately','sorry','sad','angry',
    'frustrated','disappointed','weak','loss','struggle','risk','harm']);
  const TONE_FORM = new Set(['therefore','however','furthermore','moreover','consequently',
    'subsequently','regarding','accordingly','whereas','notwithstanding','demonstrate',
    'facilitate','utilize','commence','terminate','aforementioned','pursuant']);
  const TONE_CAS  = new Set(['hey','yeah','gonna','wanna','kinda','sorta','gotta',
    'nope','yep','okay','super','totally','literally','basically','stuff','awesome','cool']);
  const TONE_HEDGE= new Set(['maybe','perhaps','might','possibly','sometimes','often',
    'usually','generally','typically','apparently','seemingly','arguably','fairly',
    'somewhat','rather','quite','very','really','actually']);

  function syllables(word) {
    word = word.toLowerCase().replace(/[^a-z]/g, '');
    if (word.length <= 3) return 1;
    word = word.replace(/(?:[^laeiouy]es|ed|[^laeiouy]e)$/, '').replace(/^y/, '');
    return (word.match(/[aeiouy]{1,2}/g) || ['x']).length;
  }

  function analyze(text) {
    const t = text.trim();
    const words = t.match(/\b[a-zA-Z''-]+\b/g) || [];
    const sents  = t.match(/[^.!?]+[.!?]+/g) || (t ? [t] : []);
    const wc = words.length, sc = sents.length;
    const chars = t.length;
    const readingTime = Math.max(1, Math.ceil(wc / 200));

    // Flesch reading ease
    const syl = words.reduce((s, w) => s + syllables(w), 0);
    const fe  = wc > 0 && sc > 0
      ? Math.max(0, Math.min(100, Math.round(206.835 - 1.015*(wc/sc) - 84.6*(syl/wc))))
      : 0;
    const readLabel = fe >= 80 ? 'Very Easy' : fe >= 70 ? 'Easy' : fe >= 60 ? 'Standard'
      : fe >= 50 ? 'Fairly Difficult' : fe >= 30 ? 'Difficult' : 'Dense';

    // Density
    const freq = {};
    for (const w of words) {
      const lw = w.toLowerCase();
      if (STOP.has(lw) || lw.length < 3) continue;
      freq[lw] = (freq[lw] || 0) + 1;
    }
    const density = Object.entries(freq).sort((a,b) => b[1]-a[1]).slice(0,10)
      .map(([word, count]) => ({
        word, count,
        pct: Math.round(count / wc * 100),
        level: count >= 4 ? 'dense' : count >= 3 ? 'heavy' : 'ok',
      }));

    // Tone
    const lw = words.map(w => w.toLowerCase());
    const pos = lw.filter(w => TONE_POS.has(w)).length;
    const neg = lw.filter(w => TONE_NEG.has(w)).length;
    const frm = lw.filter(w => TONE_FORM.has(w)).length;
    const cas = lw.filter(w => TONE_CAS.has(w)).length;
    const hdg = lw.filter(w => TONE_HEDGE.has(w)).length;
    const tone = {
      sentiment: pos > neg+1 ? 'Positive' : neg > pos+1 ? 'Negative' : 'Neutral',
      formality: frm > cas   ? 'Formal'   : cas > frm   ? 'Casual'   : 'Balanced',
      confidence: hdg/Math.max(1,wc) > 0.05 ? 'Hedged' : 'Assertive',
    };

    // Humanness (AI detection heuristic)
    const lens = sents.map(s => s.trim().split(/\s+/).length);
    const avg  = lens.reduce((a,b)=>a+b,0) / Math.max(1,lens.length);
    const cv   = Math.sqrt(lens.reduce((a,l)=>a+(l-avg)**2,0)/Math.max(1,lens.length))
                 / Math.max(1,avg);            // coefficient of variation → burstiness
    const unique = new Set(lw.filter(w=>!STOP.has(w))).size;
    const ttr    = wc > 5 ? unique / Math.max(1, lw.filter(w=>!STOP.has(w)).length) : 0.5;
    const lenScore = avg > 25 ? 0 : avg > 15 ? 0.5 : 1;
    const humanness = Math.min(100, Math.max(0,
      Math.round((Math.min(1,cv*2)*0.45 + ttr*0.35 + lenScore*0.20)*100)));

    // Word choice
    const wordChoice = density.filter(d => d.count>=2 && THESAURUS[d.word])
      .slice(0,5).map(d => ({ word: d.word, synonyms: THESAURUS[d.word] }));

    // Corrections
    const corrections = [];
    for (let i=1; i<words.length; i++)
      if (words[i].toLowerCase()===words[i-1].toLowerCase())
        corrections.push({type:'spell', text:`"${words[i]}" appears twice in a row.`});
    if (/(?<!\w)i(?!\w)/.test(t))
      corrections.push({type:'grammar', text:'Lowercase "i" found — should be "I".'});
    for (const s of sents) {
      const f = s.trim()[0];
      if (f && /[a-z]/.test(f)) {
        corrections.push({type:'grammar', text:`Sentence doesn't start with a capital: "${s.trim().slice(0,30)}…"`});
        break;
      }
    }
    if (/  +/.test(t)) corrections.push({type:'grammar', text:'Double spaces detected.'});

    return { words:wc, chars, sentences:sc, readingTime, fleschEase:fe, readLabel,
             density, tone, humanness, wordChoice, corrections };
  }

  // ── Render analysis results into the panel sections ─────────────────────
  function renderResults(r) {
    // I. Corrections
    const fixesEl = shadow.getElementById('sophia-fixes');
    fixesEl.innerHTML = r.corrections.length === 0
      ? '<p class="empty ok">Nothing flagged. Looks clean.</p>'
      : r.corrections.map(c => `
          <div class="correction-item c-${c.type}">
            <span class="c-dot"></span>
            <span class="c-text">${c.text}</span>
          </div>`).join('');

    // II. Word choice
    const repsEl = shadow.getElementById('sophia-reps');
    repsEl.innerHTML = r.wordChoice.length === 0
      ? '<p class="empty">No overused words detected.</p>'
      : r.wordChoice.map(({word, synonyms}) => `
          <div class="synonym-row">
            <span class="syn-word">${word}</span>
            <span class="syn-arrow">→</span>
            <span class="syn-list">${synonyms.slice(0,3).map(s=>`<span class="syn-chip">${s}</span>`).join('')}</span>
          </div>`).join('');

    // III. Density
    const rankEl = shadow.getElementById('sophia-rank');
    rankEl.innerHTML = r.density.length === 0
      ? '<p class="empty">Not enough text to rank.</p>'
      : r.density.map(({word,count,pct,level}) => `
          <div class="rank-row rank-${level}">
            <span class="rank-word">${word}</span>
            <div class="rank-bar-wrap"><div class="rank-bar" style="width:${Math.min(100,pct*5)}%"></div></div>
            <span class="rank-count">${count}×</span>
            <span class="rank-tag ${level}">${level==='dense'?'Too dense':level==='heavy'?'Heavy':''}</span>
          </div>`).join('');

    // IV. Counts + readability + tone + humanness
    const hCol = r.humanness >= 68 ? 'var(--sage)' : r.humanness >= 38 ? 'var(--ochre)' : 'var(--terra)';
    const hLab = r.humanness >= 68 ? 'Human-sounding' : r.humanness >= 38 ? 'Mixed signals' : 'AI-like patterns';
    shadow.getElementById('sophia-metrics').innerHTML = `
      <div class="metrics-grid">
        <div class="metric"><span class="metric-val">${r.words}</span><span class="metric-lab">words</span></div>
        <div class="metric"><span class="metric-val">${r.chars}</span><span class="metric-lab">chars</span></div>
        <div class="metric"><span class="metric-val">${r.sentences}</span><span class="metric-lab">sentences</span></div>
        <div class="metric"><span class="metric-val">${r.readingTime}m</span><span class="metric-lab">read time</span></div>
      </div>
      <div class="stat-row">
        <span class="stat-label">Readability</span>
        <span class="stat-val"><b>${r.fleschEase}</b> · ${r.readLabel}</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Tone</span>
        <span class="stat-val">${r.tone.sentiment} · ${r.tone.formality} · ${r.tone.confidence}</span>
      </div>
      <div class="stat-row" style="align-items:center;flex-direction:column;gap:6px">
        <div style="display:flex;justify-content:space-between;width:100%">
          <span class="stat-label">Humanness</span>
          <span class="humanness-score" style="color:${hCol}">${r.humanness}% · ${hLab}</span>
        </div>
        <div class="humanness-bar-bg" style="width:100%">
          <div class="humanness-bar" style="width:${r.humanness}%;background:${hCol}"></div>
        </div>
      </div>`;
  }

  // ── Page highlighting (contenteditable only) ─────────────────────────────
  function applyHighlights(el, density) {
    if (!el || !el.isContentEditable) return;
    removeHighlights(el);
    const flagged = density.filter(d => d.level !== 'ok');
    if (!flagged.length) return;

    const colorMap = {};
    for (const {word, level} of flagged)
      colorMap[word] = level === 'dense' ? 'rgba(161,75,60,.22)' : 'rgba(176,130,58,.22)';

    const pattern = Object.keys(colorMap)
      .map(w => w.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('|');
    const re = new RegExp(`\\b(${pattern})\\b`, 'gi');

    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null);
    const nodes = [];
    let n;
    while ((n = walker.nextNode()))
      if (!n.parentElement.dataset.sophiaHl) nodes.push(n);

    for (const node of nodes) {
      const text = node.textContent;
      if (!re.test(text)) continue;
      re.lastIndex = 0;
      const frag = document.createDocumentFragment();
      let last = 0, m;
      while ((m = re.exec(text)) !== null) {
        if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        const span = document.createElement('span');
        span.dataset.sophiaHl = '1';
        span.style.cssText = `background:${colorMap[m[1].toLowerCase()]};border-radius:2px;`;
        span.textContent = m[1];
        frag.appendChild(span);
        last = m.index + m[1].length;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    }
  }

  function removeHighlights(el) {
    if (!el) return;
    el.querySelectorAll('[data-sophia-hl]').forEach(s => s.replaceWith(s.textContent));
    el.normalize();
  }

  // ── Inline spell check (Grammarly-style) ─────────────────────────────
  const SPELL_DICT = {
    'teh':'the','hte':'the','adn':'and','nad':'and','waht':'what',
    'taht':'that','thta':'that','fo':'of','siad':'said','si':'is',
    'recieve':'receive','beleive':'believe','definately':'definitely',
    'seperate':'separate','occured':'occurred','accomodate':'accommodate',
    'acheive':'achieve','adress':'address','begining':'beginning',
    'buisness':'business','catagory':'category','commitee':'committee',
    'concious':'conscious','dissapear':'disappear','embarass':'embarrass',
    'enviroment':'environment','existance':'existence','familar':'familiar',
    'finaly':'finally','foriegn':'foreign','freind':'friend',
    'goverment':'government','gaurd':'guard','happend':'happened',
    'harrass':'harass','hieght':'height','immedietly':'immediately',
    'independant':'independent','intresting':'interesting','knowlege':'knowledge',
    'lisence':'license','maintainance':'maintenance','millenium':'millennium',
    'necesary':'necessary','neccessary':'necessary','noticable':'noticeable',
    'occassion':'occasion','occurance':'occurrence','ommit':'omit',
    'persistance':'persistence','posession':'possession','prefered':'preferred',
    'presance':'presence','privelege':'privilege','profesional':'professional',
    'pronounciation':'pronunciation','questionaire':'questionnaire',
    'recomend':'recommend','relevent':'relevant','religous':'religious',
    'remeber':'remember','resistence':'resistance','rythm':'rhythm',
    'sensable':'sensible','sieze':'seize','similer':'similar',
    'speach':'speech','strenght':'strength','suceed':'succeed',
    'successfull':'successful','supose':'suppose','suprise':'surprise',
    'temperture':'temperature','tendancy':'tendency','therefor':'therefore',
    'tomorow':'tomorrow','tounge':'tongue','truely':'truly',
    'untill':'until','usualy':'usually','visable':'visible',
    'wierd':'weird','wether':'whether','writting':'writing',
    'thier':'their','alot':'a lot','arguement':'argument',
    'collegue':'colleague','concensus':'consensus','deccieve':'deceive',
    'dilema':'dilemma','embarress':'embarrass','exhilerate':'exhilarate',
    'florescent':'fluorescent','forseeable':'foreseeable','futher':'further',
    'grevious':'grievous','interupt':'interrupt','lieing':'lying',
    'literaly':'literally','mischevious':'mischievous','momento':'memento',
    'neice':'niece','peice':'piece','pharoah':'pharaoh','politican':'politician',
    'pyscology':'psychology','publically':'publicly','reccomend':'recommend',
    'repitition':'repetition','restaraunt':'restaurant','revelant':'relevant',
    'seige':'siege','senario':'scenario','seperately':'separately',
    'sillouette':'silhouette','souviner':'souvenir','storys':'stories',
    'succes':'success','sucess':'success','supercede':'supersede',
    'threshhold':'threshold','tyrany':'tyranny','vaccum':'vacuum',
    'vegitable':'vegetable','wich':'which','calender':'calendar',
    'mispell':'misspell','liase':'liaise','jist':'gist',
    'managable':'manageable','accomodation':'accommodation',
    'apparantly':'apparently','brocolli':'broccoli','cemetary':'cemetery',
    'changable':'changeable','collossal':'colossal','comittee':'committee',
    'correspondance':'correspondence','dilemna':'dilemma','dissapoint':'disappoint',
    'existance':'existence','febuary':'february','fourty':'forty',
    'grammer':'grammar','greatful':'grateful','gurantee':'guarantee',
    'harrassed':'harassed','idependence':'independence','inoccent':'innocent',
    'irresistable':'irresistible','jewlery':'jewelry','judgement':'judgment',
    'liasion':'liaison','loosing':'losing','mediocre':'mediocre',
    'memeber':'member','nieghbor':'neighbor','occurence':'occurrence',
    'paralell':'parallel','passtime':'pastime','perceive':'perceive',
    'perserverance':'perseverance','personnell':'personnel','preceed':'precede',
    'privelege':'privilege','priviledge':'privilege','queing':'queuing',
    'reoccur':'recur','repetative':'repetitive','ryhme':'rhyme',
    'sacrafice':'sacrifice','seargent':'sergeant','shielf':'shield',
    'sincerely':'sincerely','skillfull':'skillful','soloution':'solution',
    'sophmore':'sophomore','suspecious':'suspicious','tatoo':'tattoo',
    'transfered':'transferred','truely':'truly','twelth':'twelfth',
    'unforgiveable':'unforgivable','unnecessarily':'unnecessarily',
    'untill':'until','upto':'up to','vacum':'vacuum','visious':'vicious',
    'weild':'wield','wierd':'weird','writting':'writing','yesterdy':'yesterday',
  };

  // Inject page-level styles for spell-mark underlines (outside shadow DOM)
  if (!document.querySelector('[data-sophia-spell-styles]')) {
    const ps = document.createElement('style');
    ps.setAttribute('data-sophia-spell-styles', '1');
    ps.textContent = `
      [data-sophia-spell] {
        border-bottom: 2px solid rgba(201,110,92,.85);
        cursor: pointer;
        border-radius: 0;
      }
      [data-sophia-spell]:hover {
        background: rgba(201,110,92,.08);
      }
    `;
    (document.head || document.documentElement).appendChild(ps);
  }

  // ── Inline tip shadow DOM ─────────────────────────────────────────────
  const tipHost = document.createElement('div');
  tipHost.id = 'sophia-inline-tip';
  Object.assign(tipHost.style, {
    position: 'fixed', top: '0', left: '0',
    zIndex: '2147483645', pointerEvents: 'none',
  });
  document.documentElement.appendChild(tipHost);
  const tipShadow = tipHost.attachShadow({ mode: 'open' });

  const tipStyleEl = document.createElement('style');
  tipStyleEl.textContent = `
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    .tc {
      position: fixed;
      background: #fff;
      border: 1px solid #dddbd0;
      border-radius: 8px;
      padding: 11px 13px 10px;
      box-shadow: 0 4px 20px rgba(20,15,5,.13), 0 1px 4px rgba(20,15,5,.07);
      font-family: system-ui, -apple-system, sans-serif;
      font-size: 13px;
      display: none;
      min-width: 185px;
      pointer-events: all;
      user-select: none;
    }
    .tc.show { display: block; }
    .tc-head {
      display: flex;
      align-items: center;
      gap: 7px;
      margin-bottom: 9px;
      padding-bottom: 9px;
      border-bottom: 1px solid #e8e6dc;
      font-size: 11px;
      letter-spacing: .1em;
      text-transform: uppercase;
      color: #9b998e;
      font-weight: 600;
    }
    .tc-row {
      display: flex;
      align-items: center;
      gap: 9px;
      margin-bottom: 9px;
    }
    .tc-wrong { color: #c96e5c; font-weight: 600; font-size: 15px; text-decoration: line-through; }
    .tc-arrow { color: #c4c2b7; font-size: 13px; }
    .tc-right  { color: #76845e; font-weight: 700; font-size: 15px; }
    .tc-actions { display: flex; gap: 7px; }
    .tc-btn {
      flex: 1;
      appearance: none;
      border: 1px solid #dddbd0;
      background: #f6f6f5;
      cursor: pointer;
      font-family: system-ui, sans-serif;
      font-size: 11.5px;
      font-weight: 600;
      padding: 6px 10px;
      border-radius: 4px;
      color: #3a3a32;
      transition: background .12s;
      letter-spacing: .02em;
    }
    .tc-btn:hover { background: #eceae3; }
    .tc-btn.accept { background: #76845e; color: #fff; border-color: #76845e; }
    .tc-btn.accept:hover { background: #5f6c4a; }
  `;
  const tipWrapper = document.createElement('div');
  tipWrapper.innerHTML = `
    <div class="tc" id="tc">
      <div class="tc-head">Sophia suggests</div>
      <div class="tc-row">
        <span class="tc-wrong" id="tc-wrong"></span>
        <span class="tc-arrow">→</span>
        <span class="tc-right" id="tc-right"></span>
      </div>
      <div class="tc-actions">
        <button class="tc-btn accept" id="tc-accept">Accept</button>
        <button class="tc-btn" id="tc-dismiss">Dismiss</button>
      </div>
    </div>
  `;
  tipShadow.appendChild(tipStyleEl);
  tipShadow.appendChild(tipWrapper);

  const tipCard    = tipShadow.getElementById('tc');
  const tcWrong    = tipShadow.getElementById('tc-wrong');
  const tcRight    = tipShadow.getElementById('tc-right');
  const tcAccept   = tipShadow.getElementById('tc-accept');
  const tcDismiss  = tipShadow.getElementById('tc-dismiss');
  let   tipTarget  = null; // the [data-sophia-spell] span currently focused

  function showInlineTip(span) {
    tipTarget = span;
    const r = span.getBoundingClientRect();
    tcWrong.textContent  = span.textContent;
    tcRight.textContent  = span.dataset.sophiaSpell;
    tipCard.classList.add('show');
    tipHost.style.pointerEvents = 'auto';
    // Position below word
    const top  = Math.min(r.bottom + 6, window.innerHeight - 140);
    const left = Math.max(4, Math.min(r.left, window.innerWidth - 200));
    tipCard.style.top  = top  + 'px';
    tipCard.style.left = left + 'px';
  }

  function hideInlineTip() {
    tipCard.classList.remove('show');
    tipHost.style.pointerEvents = 'none';
    tipTarget = null;
  }

  tcAccept.addEventListener('click', (e) => {
    e.stopPropagation();
    if (!tipTarget) { hideInlineTip(); return; }
    const correction = tipTarget.dataset.sophiaSpell;
    tipTarget.replaceWith(document.createTextNode(correction));
    hideInlineTip();
  });

  tcDismiss.addEventListener('click', (e) => {
    e.stopPropagation();
    if (tipTarget) {
      tipTarget.removeAttribute('data-sophia-spell');
      tipTarget.style.borderBottom = '';
    }
    hideInlineTip();
  });

  // Hide tip when clicking elsewhere
  document.addEventListener('click', (e) => {
    if (!tipTarget) return;
    if (e.target && e.target.dataset && e.target.dataset.sophiaSpell) return;
    hideInlineTip();
  }, true);

  // Click on page spell marks
  document.addEventListener('click', (e) => {
    const span = e.target.closest('[data-sophia-spell]');
    if (!span) return;
    e.stopPropagation();
    showInlineTip(span);
  }, true);

  function getCaretOffset(el) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return -1;
    const r   = sel.getRangeAt(0);
    const pre = r.cloneRange();
    pre.selectNodeContents(el);
    pre.setEnd(r.endContainer, r.endOffset);
    return pre.toString().length;
  }

  function restoreCaretOffset(el, offset) {
    if (offset < 0) return;
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let pos = 0, node;
    while ((node = walker.nextNode())) {
      const len = node.length;
      if (pos + len >= offset) {
        try {
          const range = document.createRange();
          range.setStart(node, offset - pos);
          range.collapse(true);
          const sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(range);
        } catch(_) {}
        return;
      }
      pos += len;
    }
  }

  function clearSpellMarks(el) {
    if (!el) return;
    el.querySelectorAll('[data-sophia-spell]').forEach(s => {
      s.replaceWith(document.createTextNode(s.textContent));
    });
    el.normalize();
  }

  function applySpellMarks(el) {
    if (!el || !el.isContentEditable) return;
    hideInlineTip();
    const offset = getCaretOffset(el);
    clearSpellMarks(el);

    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const p = node.parentElement;
        if (!p) return NodeFilter.FILTER_REJECT;
        const t = p.tagName && p.tagName.toLowerCase();
        if (t === 'script' || t === 'style' || t === 'code') return NodeFilter.FILTER_REJECT;
        if (p.dataset.sophiaSpell || p.dataset.sophiaHl) return NodeFilter.FILTER_SKIP;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    const nodes = [];
    let n;
    while ((n = walker.nextNode())) nodes.push(n);

    for (const node of nodes) {
      const text = node.textContent;
      const wordRe = /\b([a-zA-Z]{2,})\b/g;
      let m;
      const matches = [];
      while ((m = wordRe.exec(text)) !== null) {
        const w = m[1].toLowerCase();
        if (SPELL_DICT[w]) matches.push({ idx: m.index, len: m[0].length, word: m[0], fix: SPELL_DICT[w] });
      }
      if (!matches.length) continue;

      const frag = document.createDocumentFragment();
      let last = 0;
      for (const { idx, len, word, fix } of matches) {
        if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
        const span = document.createElement('span');
        span.dataset.sophiaSpell = fix;
        span.textContent = word;
        frag.appendChild(span);
        last = idx + len;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    }

    restoreCaretOffset(el, offset);
  }

  // ── Textarea spell check (floating issues card) ───────────────────────
  // For textarea/input we can't inject spans, so we float a card nearby.

  const taIssueHosts = new WeakMap(); // textarea → host element for issues card

  function spellCheckTextarea(ta) {
    const text  = ta.value || '';
    const words = text.match(/\b([a-zA-Z]{2,})\b/g) || [];
    const issues = [];
    const seen   = new Set();
    for (const w of words) {
      const lc = w.toLowerCase();
      if (SPELL_DICT[lc] && !seen.has(lc)) {
        seen.add(lc);
        issues.push({ word: w, fix: SPELL_DICT[lc] });
      }
    }

    // Remove old card if exists
    let card = taIssueHosts.get(ta);
    if (card) { card.remove(); taIssueHosts.delete(ta); }
    if (!issues.length) return;

    // Build floating card anchored to the field
    const r = ta.getBoundingClientRect();
    card = document.createElement('div');
    card.setAttribute('data-sophia-ta-issues', '1');
    Object.assign(card.style, {
      position:   'fixed',
      top:        (r.bottom + 6) + 'px',
      left:       r.left + 'px',
      zIndex:     '2147483644',
      background: '#fff',
      border:     '1px solid #dddbd0',
      borderRadius: '7px',
      boxShadow:  '0 4px 18px rgba(20,15,5,.12)',
      fontFamily: 'system-ui, sans-serif',
      fontSize:   '12.5px',
      padding:    '10px 12px',
      maxWidth:   '240px',
      pointerEvents: 'all',
    });

    const header = document.createElement('div');
    Object.assign(header.style, {
      fontSize:      '9px',
      letterSpacing: '.18em',
      textTransform: 'uppercase',
      fontWeight:    '700',
      color:         '#9b998e',
      marginBottom:  '8px',
    });
    header.textContent = `Sophia · ${issues.length} spelling issue${issues.length > 1 ? 's' : ''}`;
    card.appendChild(header);

    for (const { word, fix } of issues) {
      const row = document.createElement('div');
      Object.assign(row.style, {
        display:       'flex',
        alignItems:    'center',
        gap:           '7px',
        padding:       '4px 0',
        borderTop:     '1px solid #eee',
      });

      const wrong = document.createElement('span');
      Object.assign(wrong.style, { color: '#c96e5c', fontWeight: '600', flex: '1', textDecoration: 'line-through' });
      wrong.textContent = word;

      const arrow = document.createElement('span');
      arrow.style.color = '#c4c2b7';
      arrow.textContent = '→';

      const right = document.createElement('span');
      Object.assign(right.style, { color: '#76845e', fontWeight: '700', flex: '1' });
      right.textContent = fix;

      const btn = document.createElement('button');
      Object.assign(btn.style, {
        appearance: 'none', border: '1px solid #dddbd0', background: '#76845e',
        color: '#fff', fontFamily: 'inherit', fontSize: '10.5px', fontWeight: '600',
        padding: '3px 8px', borderRadius: '3px', cursor: 'pointer', flexShrink: '0',
      });
      btn.textContent = 'Fix';
      btn.addEventListener('click', () => {
        const re = new RegExp('\\b' + word.replace(/[.*+?^${}()|[\]\\]/g,'\\$&') + '\\b');
        ta.value = ta.value.replace(re, fix);
        ta.dispatchEvent(new Event('input'));
        row.style.opacity = '.4';
        row.style.pointerEvents = 'none';
      });

      row.appendChild(wrong);
      row.appendChild(arrow);
      row.appendChild(right);
      row.appendChild(btn);
      card.appendChild(row);
    }

    // Dismiss on click outside
    const dismissTA = (ev) => {
      if (!card.contains(ev.target) && ev.target !== ta) {
        card.remove(); taIssueHosts.delete(ta);
        document.removeEventListener('click', dismissTA, true);
      }
    };
    setTimeout(() => document.addEventListener('click', dismissTA, true), 0);

    document.documentElement.appendChild(card);
    taIssueHosts.set(ta, card);
  }

  // Watch contenteditable AND textarea/input elements
  const spellTimers = new WeakMap();
  document.addEventListener('input', (e) => {
    const el = e.target;
    if (!el) return;
    clearTimeout(spellTimers.get(el));
    if (el.isContentEditable) {
      spellTimers.set(el, setTimeout(() => applySpellMarks(el), 1200));
    } else if (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && el.type === 'text')) {
      spellTimers.set(el, setTimeout(() => spellCheckTextarea(el), 1200));
    }
  }, true);

  // Also clear spell marks when highlights are removed (keeps DOM clean)
  const _origRemoveHighlights = removeHighlights;

  // ── Bubble helpers ────────────────────────────────────────────────────

  function setBubbleWorking(on) {
    if (on) bubbleBtn.classList.add('working');
    else    bubbleBtn.classList.remove('working');
  }

  // Theme is 'system' (the default when unset), 'dawn' or 'dusk'. System follows the
  // OS light/dark setting live, through the browser's prefers-color-scheme query.
  const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
  function themeMode(theme) {
    if (theme === 'dusk' || theme === 'dark') return 'dusk';
    if (theme === 'dawn') return 'dawn';
    return 'system';
  }
  function isDusk(theme) {
    const mode = themeMode(theme);
    return mode === 'dusk' || (mode === 'system' && darkQuery.matches);
  }

  function applySettings(s) {
    bubbleHost.style.display = s.showBubble === false ? 'none' : 'block';
    if (isDusk(s.theme)) panel.classList.add('dusk');
    else panel.classList.remove('dusk');
  }

  // Apply saved settings on page load (bubble visibility + theme).
  chrome.storage.local.get('sophia-settings', (data) => {
    applySettings(data['sophia-settings'] || {});
  });

  // React to settings changes in real time (e.g. options page open in another tab).
  // The OS flipped light/dark: only matters while the theme follows the system.
  darkQuery.addEventListener('change', () => {
    chrome.storage.local.get('sophia-settings', (data) => {
      applySettings(data['sophia-settings'] || {});
    });
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !changes['sophia-settings']) return;
    const next = changes['sophia-settings'].newValue || {};
    applySettings(next);
    // Keep an open drawer in sync with the options page / popup.
    if (drawerOpen) paintDrawerSettings(next);
  });

  // ── Bubble interaction (drag + tap) ──────────────────────────────────
  //
  // We avoid the `click` event entirely: `preventDefault()` on mousedown
  // suppresses `click` in Chrome, and shadow→host event bubbling is fragile
  // across page contexts. Instead we detect taps via mousedown + mouseup
  // with a movement threshold — completely reliable on any DOM element.

  bubbleHost.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    bdDragging   = true;
    bdWasDragged = false;
    const rect = bubbleHost.getBoundingClientRect();
    bdOffX   = e.clientX - rect.left;
    bdOffY   = e.clientY - rect.top;
    bdStartX = e.clientX;
    bdStartY = e.clientY;
    bubbleHost.style.cursor = 'grabbing';
    // No preventDefault / stopPropagation — let the browser keep normal flow
  });

  document.addEventListener('mousemove', (e) => {
    if (!bdDragging) return;
    if (Math.abs(e.clientX - bdStartX) > 4 || Math.abs(e.clientY - bdStartY) > 4)
      bdWasDragged = true;
    const x = Math.max(0, Math.min(e.clientX - bdOffX, window.innerWidth  - 52));
    const y = Math.max(0, Math.min(e.clientY - bdOffY, window.innerHeight - 52));
    bubbleHost.style.left = x + 'px';
    bubbleHost.style.top  = y + 'px';
  });

  document.addEventListener('mouseup', () => {
    if (!bdDragging) return;
    bdDragging = false;
    bubbleHost.style.cursor = 'grab';

    if (!bdWasDragged) {
      // ── Tap: open / close the Sophia panel ──────────────────────────
      if (panelVisible) {
        hidePanel();
      } else {
        const br = bubbleHost.getBoundingClientRect();
        const x  = Math.max(20, br.left - 420);
        const y  = Math.max(20, Math.min(br.top, window.innerHeight - 500));
        showPanel(x, y, currentText, currentElement);
      }
    } else {
      // ── Drag ended: save position ────────────────────────────────────
      chrome.storage.local.set({
        'sophia-bubble-pos': {
          top:  parseFloat(bubbleHost.style.top)  || 0,
          left: parseFloat(bubbleHost.style.left) || 0,
        }
      });
      bdWasDragged = false;
    }
  });

  // Restore saved bubble position on load
  chrome.storage.local.get('sophia-bubble-pos', (data) => {
    const p = data['sophia-bubble-pos'];
    if (p) {
      bubbleHost.style.top  = Math.max(0, Math.min(p.top,  window.innerHeight - 52)) + 'px';
      bubbleHost.style.left = Math.max(0, Math.min(p.left, window.innerWidth  - 52)) + 'px';
    }
  });

  // ── Drag to move ─────────────────────────────────────────────────────
  // We move the HOST (a plain page element with position:fixed), not the
  // shadow panel. This is unambiguous: host.style.left/top are always
  // viewport-relative, no Shadow DOM coordinate questions involved.
  // document.mousemove on the outer page fires reliably for any DOM drag.

  panelHead.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    if (e.target.closest('button')) return; // let menu/close handle themselves
    e.preventDefault(); // prevent page text selection during drag
    dragging = true;
    const rect = host.getBoundingClientRect();
    drOffX = e.clientX - rect.left;
    drOffY = e.clientY - rect.top;
    panelHead.classList.add('dragging');
    document.documentElement.style.cursor = 'grabbing';
  });

  // ── Resize ────────────────────────────────────────────────────────────

  resizeHandle.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    resizing = true;
    rsStartX = e.clientX;
    rsStartY = e.clientY;
    rsStartW = host.offsetWidth;
    rsStartH = panel.offsetHeight || host.offsetHeight;
    document.documentElement.style.cursor = 'nwse-resize';
  });

  // ── Shared document-level tracking ────────────────────────────────────

  document.addEventListener('mousemove', (e) => {
    if (dragging) {
      const { left, top } = clamp(e.clientX - drOffX, e.clientY - drOffY, host.offsetWidth);
      host.style.left = left + 'px';
      host.style.top  = top  + 'px';
    }
    if (resizing) {
      const newW = Math.max(MIN_W, Math.min(MAX_W, rsStartW + (e.clientX - rsStartX)));
      const newH = Math.max(MIN_H, Math.min(MAX_H, rsStartH + (e.clientY - rsStartY)));
      host.style.width   = newW + 'px';
      panel.style.height = newH + 'px';
      userResized = true;
    }
  });

  document.addEventListener('mouseup', (e) => {
    if (dragging || resizing) {
      dragging = resizing = false;
      panelHead.classList.remove('dragging');
      document.documentElement.style.cursor = '';
      if (panelVisible) saveState();
      return;
    }

    if (e.composedPath().includes(host)) return;

    setTimeout(() => {
      const el = document.activeElement;
      if (!isEditable(el)) { hidePanel(); return; }
      const text = getSelectedText(el);
      if (text.trim().length < 3) { hidePanel(); return; }
      showPanel(e.clientX, e.clientY, text, el);
    }, 0);
  });

  // ── Keyboard selection detection ──────────────────────────────────────

  /*
   * The mouseup path above covers mouse-based selections.
   * This covers Shift+Arrow keyboard selections.
   */
  document.addEventListener('keyup', (e) => {
    const isSelectionKey = e.shiftKey ||
      ['Home', 'End', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key);
    if (!isSelectionKey) return;

    const el = document.activeElement;
    if (!isEditable(el)) return;

    const text = getSelectedText(el);
    if (text.trim().length < 3) { hidePanel(); return; }

    // For keyboard selections there's no mouse position; anchor near the element.
    const rect = el.getBoundingClientRect();
    showPanel(rect.right - 20, rect.bottom, text, el);
  });

  // ── Button listeners ──────────────────────────────────────────────────

  closeBtn.addEventListener('click', hidePanel);

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    // Escape peels one layer at a time: drawer first, then the panel.
    if (drawerOpen)        closeDrawer();
    else if (panelVisible) hidePanel();
  });

  // ══════════════════════════════════════════════════════════════════════
  //  Step 7 — Overview drawer
  //
  //  Three jobs: greet the user with a rotating piece of wisdom, give a
  //  read of the WHOLE page (not just the selection), and hold the
  //  personalization controls in one place.
  //
  //  Everything here is local. The quotes come from a bundled JSON file
  //  over the chrome-extension:// scheme — no network, and if that read
  //  fails for any reason we fall back to an inline set rather than
  //  showing an empty drawer.
  // ══════════════════════════════════════════════════════════════════════

  const drawer      = shadow.getElementById('sophia-drawer');
  const scrim       = shadow.getElementById('sophia-scrim');
  const drawerClose = shadow.getElementById('sophia-drawer-close');
  const greetEl     = shadow.getElementById('sophia-greeting');
  const quoteTextEl = shadow.getElementById('sophia-quote-text');
  const quoteSrcEl  = shadow.getElementById('sophia-quote-src');
  const ovGrid      = shadow.getElementById('sophia-ov-grid');
  const ovWords     = shadow.getElementById('sophia-ov-words');
  const ovRefresh   = shadow.getElementById('sophia-ov-refresh');
  const nameInput   = shadow.getElementById('sophia-name');

  let drawerOpen = false;
  let quotes     = null;
  let quoteIdx   = Math.floor(Date.now() / 864e5); // day index — stable per day

  // Escape anything that came from the page before it touches innerHTML.
  function esc(s) {
    return String(s).replace(/[&<>"']/g, c =>
      ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  }

  const FALLBACK_QUOTES = [
    { text: 'You have power over your mind — not outside events. Realize this, and you will find strength.', source: 'Marcus Aurelius' },
    { text: 'We suffer more often in imagination than in reality.', source: 'Seneca' },
    { text: 'In the multitude of words there wanteth not sin: but he that refraineth his lips is wise.', source: 'Proverbs 10:19' },
  ];

  async function loadQuotes() {
    if (quotes) return quotes;
    try {
      const res  = await fetch(chrome.runtime.getURL('data/quotes.json'));
      const json = await res.json();
      if (Array.isArray(json) && json.length) return (quotes = json);
    } catch (_) {
      // Bundled file unreadable (unpacked reload, blocked scheme) — degrade.
    }
    return (quotes = FALLBACK_QUOTES);
  }

  async function showQuote() {
    const list = await loadQuotes();
    const q = list[((quoteIdx % list.length) + list.length) % list.length];
    quoteTextEl.textContent = '“' + q.text + '”';
    quoteSrcEl.textContent  = q.source;
  }

  function greetingFor(name) {
    const h = new Date().getHours();
    const part = h < 5  ? 'Still awake'
               : h < 12 ? 'Good morning'
               : h < 17 ? 'Good afternoon'
               : h < 22 ? 'Good evening'
               :          'Good night';
    return name ? `${part}, <b>${esc(name)}</b>.` : `${part}.`;
  }

  // ── Whole-page text ────────────────────────────────────────────────────
  //
  // Sophia's own UI is appended to document.documentElement, not body, so
  // walking body already excludes the panel, orb and correction cards —
  // no need for a costly closest() test on every text node.

  const SCAN_BUDGET = 120000; // chars — keeps the scan instant on huge pages
  const SCAN_MAX_BLOCKS = 400; // ceiling on the per-block corrections pass

  // Returns the page as a list of BLOCKS (paragraphs, headings, list items),
  // not one flat string. The distinction matters: rules like "this word
  // appears twice in a row" would fire on every boundary where a nav label
  // happens to repeat a heading if we glued the page together first.
  function collectPageBlocks() {
    if (!document.body) return [];

    // innerText, not textContent: it gives what a READER sees — it honours
    // CSS visibility, drops script/style, and breaks blocks with newlines.
    let raw = '';
    try { raw = document.body.innerText || ''; } catch (_) { return []; }

    const blocks = [];
    let used = 0;
    for (const line of raw.split('\n')) {
      if (used >= SCAN_BUDGET) break;
      const t = line.trim();
      if (!t) continue;
      blocks.push(t);
      used += t.length + 1;
    }

    // Editable fields keep their text in .value, where innerText can't see it.
    for (const el of document.querySelectorAll('textarea, input[type="text"]')) {
      if (used >= SCAN_BUDGET) break;
      const v = (el.value || '').trim();
      if (!v) continue;
      blocks.push(v);
      used += v.length + 1;
    }

    return blocks;
  }

  // Headings and list items rarely end in punctuation. Terminating them keeps
  // the readability score honest — otherwise a whole page collapses into one
  // enormous "sentence" and every score reads as unreadably dense.
  function terminate(s) { return /[.!?:;]$/.test(s) ? s : s + '.'; }

  function renderPageOverview() {
    const blocks = collectPageBlocks();
    const text   = blocks.map(terminate).join(' ');

    if (!text || text.split(/\s+/).length < 10) {
      ovGrid.innerHTML  = '';
      ovWords.innerHTML = '<p class="ov-empty">Not enough readable text on this page to judge.</p>';
      return;
    }

    // Stats and density are page-wide; corrections are counted per block so
    // no rule can fire across a boundary between two unrelated blocks.
    const r = analyze(text);
    let issues = 0;
    for (const b of blocks.slice(0, SCAN_MAX_BLOCKS)) issues += analyze(b).corrections.length;

    ovGrid.innerHTML = `
      <div class="ov-cell">
        <div class="ov-num">${r.words.toLocaleString()}</div>
        <div class="ov-cap">Words</div>
      </div>
      <div class="ov-cell">
        <div class="ov-num">${r.readingTime}<small> min</small></div>
        <div class="ov-cap">Reading time</div>
      </div>
      <div class="ov-cell${issues > 0 ? ' flag' : ''}">
        <div class="ov-num">${issues}</div>
        <div class="ov-cap">Open issues</div>
      </div>
      <div class="ov-cell${r.fleschEase < 50 ? ' warn' : ''}">
        <div class="ov-num">${r.fleschEase}</div>
        <div class="ov-cap">${esc(r.readLabel)}</div>
      </div>`;

    const top = r.density.slice(0, 8);
    ovWords.innerHTML = top.length === 0
      ? '<p class="ov-empty">No word dominates this page.</p>'
      : top.map(d => `
          <span class="ov-chip ${d.level}">
            <b>${esc(d.word)}</b><span class="c">${d.count}</span>
          </span>`).join('');
  }

  // ── Preferences wiring ────────────────────────────────────────────────
  //
  // The drawer and the options page edit the SAME settings object, so every
  // write here is read-modify-write. Never clobber keys we don't own.

  const TOGGLES = {
    'sophia-t-spelling':    'spelling',
    'sophia-t-grammar':     'grammar',
    'sophia-t-density':     'density',
    'sophia-t-readability': 'readability',
    'sophia-t-bubble':      'showBubble',
  };

  function readSettings() {
    return new Promise(resolve => {
      chrome.storage.local.get('sophia-settings', d => resolve(d['sophia-settings'] || {}));
    });
  }

  async function patchSettings(patch) {
    const current = await readSettings();
    const next = Object.assign({}, current, patch);
    await chrome.storage.local.set({ 'sophia-settings': next });
    return next;
  }

  function paintDrawerSettings(s) {
    greetEl.innerHTML = greetingFor(s.name);
    if (document.activeElement !== nameInput) nameInput.value = s.name || '';

    const mode = themeMode(s.theme);
    for (const m of ['system', 'dawn', 'dusk']) {
      shadow.getElementById(`sophia-theme-${m}`).classList.toggle('on', m === mode);
    }

    // Every check defaults ON — absent key means "not yet configured".
    for (const [id, key] of Object.entries(TOGGLES)) {
      const el = shadow.getElementById(id);
      const on = s[key] !== false;
      el.classList.toggle('on', on);
      el.setAttribute('aria-checked', String(on));
    }

    const ai = shadow.getElementById('sophia-t-ai');
    ai.classList.remove('on');
    ai.setAttribute('aria-checked', 'false');
  }

  for (const [id, key] of Object.entries(TOGGLES)) {
    shadow.getElementById(id).addEventListener('click', async () => {
      const s = await readSettings();
      const next = await patchSettings({ [key]: s[key] === false });
      paintDrawerSettings(next);
      applySettings(next);
    });
  }

  for (const id of ['sophia-theme-system', 'sophia-theme-dawn', 'sophia-theme-dusk']) {
    shadow.getElementById(id).addEventListener('click', async (e) => {
      const next = await patchSettings({ theme: e.currentTarget.dataset.theme });
      paintDrawerSettings(next);
      applySettings(next);
    });
  }

  let nameTimer;
  nameInput.addEventListener('input', () => {
    clearTimeout(nameTimer);
    nameTimer = setTimeout(async () => {
      const next = await patchSettings({ name: nameInput.value.trim() });
      greetEl.innerHTML = greetingFor(next.name);
    }, 500);
  });

  // Typing in the drawer must never reach the host page's shortcuts.
  // Because this stops propagation before document, Escape is handled here.
  drawer.addEventListener('keydown', (e) => {
    e.stopPropagation();
    if (e.key === 'Escape') closeDrawer();
  });

  // ── Open / close ──────────────────────────────────────────────────────

  async function openDrawer() {
    if (drawerOpen) return;
    drawerOpen = true;
    drawer.hidden = false;
    // Next frame, so the transform transition actually runs.
    requestAnimationFrame(() => {
      drawer.classList.add('show');
      scrim.classList.add('show');
    });
    menuBtn.setAttribute('aria-expanded', 'true');

    paintDrawerSettings(await readSettings());
    quoteIdx++;                 // rotate on every open
    showQuote();
    renderPageOverview();       // fresh read of the page each time
    drawerClose.focus();
  }

  // refocus=false when the whole panel is going away, so we don't yank
  // focus back to a button that's about to become invisible.
  function closeDrawer(refocus = true) {
    if (!drawerOpen) return;
    drawerOpen = false;
    drawer.classList.remove('show');
    scrim.classList.remove('show');
    menuBtn.setAttribute('aria-expanded', 'false');
    // Keep it out of the tab order once the slide-out has finished.
    setTimeout(() => { if (!drawerOpen) drawer.hidden = true; }, 300);
    if (refocus) menuBtn.focus();
  }

  menuBtn.setAttribute('aria-expanded', 'false');
  menuBtn.addEventListener('click', () => drawerOpen ? closeDrawer() : openDrawer());
  drawerClose.addEventListener('click', closeDrawer);
  scrim.addEventListener('click', closeDrawer);
  ovRefresh.addEventListener('click', renderPageOverview);

  refineBtn.addEventListener('click', () => {
    if (!currentText) return;
    waveEl.classList.add('active');
    setBubbleWorking(true);
    // Run analysis on the next tick so the wave animation has time to render.
    setTimeout(() => {
      const result = analyze(currentText);
      lastAnalysis = result;
      chrome.storage.local.set({ 'sophia-last-analysis': result });
      renderResults(result);
      applyHighlights(currentElement, result.density);
      applySpellMarks(currentElement);
      resultsEl.classList.add('show');
      waveEl.classList.remove('active');
      setBubbleWorking(false);
    }, 420);
  });

  // ── Popup ↔ content script messaging ─────────────────────────────────
  //
  // The popup (toolbar dropdown) sends messages here to query status or
  // trigger actions without needing direct DOM access to the host page.
  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg.type === 'PING') {
      const sel = window.getSelection()?.toString() || '';
      sendResponse({ ok: true, selection: sel.length });
      return true;
    }
    if (msg.type === 'GET_STATUS') {
      const words = currentText
        ? currentText.trim().split(/\s+/).filter(Boolean).length
        : 0;
      sendResponse({ visible: panelVisible, text: currentText, words });
      return true;
    }
    if (msg.type === 'GET_ANALYSIS') {
      sendResponse({ result: lastAnalysis });
      return true;
    }
    if (msg.type === 'TRIGGER_ANALYZE') {
      showPanel(window.innerWidth / 2 - 190, 80, currentText, currentElement);
      sendResponse({ ok: true });
      return true;
    }
    if (msg.type === 'SHOW_PANEL') {
      showPanel(window.innerWidth / 2 - 190, 80, currentText, currentElement);
      sendResponse({ ok: true });
      return true;
    }
    if (msg.type === 'HIDE_PANEL') {
      hidePanel();
      sendResponse({ ok: true });
      return true;
    }
    if (msg.type === 'SET_HIGHLIGHTS') {
      if (msg.on && lastAnalysis && currentElement) {
        applyHighlights(currentElement, lastAnalysis.density);
      } else if (!msg.on && currentElement) {
        removeHighlights(currentElement);
      }
      sendResponse({ ok: true });
      return true;
    }
    if (msg.type === 'ANALYZE_TEXT') {
      const result = analyze(msg.text || '');
      lastAnalysis = result;
      chrome.storage.local.set({ 'sophia-last-analysis': result });
      sendResponse({ result });
      return true;
    }
    if (msg.type === 'SET_BUBBLE') {
      bubbleHost.style.display = msg.show ? 'block' : 'none';
      sendResponse({ ok: true });
      return true;
    }
  });

})();
