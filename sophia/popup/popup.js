'use strict';

const STORAGE_KEY = 'sophia-settings';

const QUIPS = [
  "What are we crafting today?",
  "Ready when you are.",
  "Words await your attention.",
  "Let's make it sing.",
  "Every sentence is a choice.",
  "The page is yours.",
  "Watching over your prose.",
];

// ── Utilities ─────────────────────────────────────────────────────────────────

// Theme is 'system' (the default when unset), 'dawn' or 'dusk'; system follows the OS.
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
function themeMode(t) { return t === 'dusk' || t === 'dark' ? 'dusk' : t === 'dawn' ? 'dawn' : 'system'; }
function isDusk(t) { const m = themeMode(t); return m === 'dusk' || (m === 'system' && darkQuery.matches); }

function fmtNum(n) {
  if (n == null || n === '') return '—';
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return String(n);
}

function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : '—'; }

function humanColor(pct) {
  if (pct >= 72) return '#76845e';
  if (pct >= 48) return '#d4a65e';
  return '#c96e5c';
}
function humanLabel(pct) {
  if (pct >= 85) return 'Very human — natural rhythm and variety';
  if (pct >= 70) return 'Mostly human — a few patterns to vary';
  if (pct >= 50) return 'Borderline — sentence rhythm feels uniform';
  if (pct >= 30) return 'AI-like patterns in structure';
  return 'Highly AI-like — low variety, high uniformity';
}

function readColor(ease) {
  if (ease >= 70) return '#76845e';
  if (ease >= 50) return '#d4a65e';
  return '#c96e5c';
}
function readLabel(ease) {
  if (ease >= 90) return 'Very Easy';
  if (ease >= 70) return 'Easy';
  if (ease >= 60) return 'Standard';
  if (ease >= 50) return 'Fairly Difficult';
  if (ease >= 30) return 'Difficult';
  return 'Very Difficult';
}

async function sendToPage(msg) {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.id) return null;
    return await chrome.tabs.sendMessage(tab.id, msg);
  } catch { return null; }
}

// ── Theme ─────────────────────────────────────────────────────────────────────

function applyTheme(theme) {
  if (isDusk(theme)) {
    document.body.setAttribute('data-theme', 'dark');
  } else {
    document.body.removeAttribute('data-theme');
  }
  // Highlight the active segment button
  document.querySelectorAll('.tseg').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === themeMode(theme));
  });
}

// ── Tab switching ─────────────────────────────────────────────────────────────

function initTabs() {
  const tabs   = document.querySelectorAll('.tab');
  const panels = document.querySelectorAll('.tab-panel');
  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      tabs.forEach(t => { t.classList.remove('active'); t.setAttribute('aria-selected','false'); });
      panels.forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      btn.setAttribute('aria-selected', 'true');
      document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    });
  });
}

function switchTab(name) {
  document.querySelectorAll('.tab').forEach(t => {
    t.classList.toggle('active', t.dataset.tab === name);
    t.setAttribute('aria-selected', String(t.dataset.tab === name));
  });
  document.querySelectorAll('.tab-panel').forEach(p => {
    p.classList.toggle('active', p.id === 'tab-' + name);
  });
}

// ── Render analysis results ───────────────────────────────────────────────────

function renderInsights(r) {
  document.getElementById('insights-empty').style.display = 'none';
  document.getElementById('insights-data').style.display  = '';

  // 5-cell grid
  const rt = (!r.readingTime || r.readingTime < 1) ? '<1m' : r.readingTime + 'm';
  const sentences = r.sentences || 0;
  const avgSentLen = sentences > 0 ? Math.round((r.words || 0) / sentences) : 0;
  document.getElementById('ins-grid').innerHTML = `
    <div class="m-cell"><span class="m-val">${fmtNum(r.words)}</span><span class="m-lab">Words</span></div>
    <div class="m-cell"><span class="m-val">${fmtNum(r.chars)}</span><span class="m-lab">Chars</span></div>
    <div class="m-cell"><span class="m-val">${fmtNum(sentences)}</span><span class="m-lab">Sentences</span></div>
    <div class="m-cell"><span class="m-val">${avgSentLen || '—'}</span><span class="m-lab">Avg/Sent</span></div>
    <div class="m-cell"><span class="m-val" style="font-size:14px">${rt}</span><span class="m-lab">Read</span></div>
  `;

  // Score bars
  const ease = r.fleschEase ?? 0;
  const hum  = Math.round(r.humanness ?? 50);
  const easeColor = readColor(ease);
  const humColor  = humanColor(hum);
  document.getElementById('ins-scores').innerHTML = `
    <div class="score-row">
      <div class="score-head">
        <span class="score-key">Readability</span>
        <span class="score-val" style="color:${easeColor}">${ease}/100</span>
      </div>
      <div class="bar-bg"><div class="bar-fill" style="width:${ease}%;background:${easeColor}"></div></div>
      <div class="score-desc">${r.readLabel || readLabel(ease)}</div>
    </div>
    <div class="score-row">
      <div class="score-head">
        <span class="score-key">Humanness</span>
        <span class="score-val" style="color:${humColor}">${hum}%</span>
      </div>
      <div class="bar-bg"><div class="bar-fill" style="width:${hum}%;background:${humColor}"></div></div>
      <div class="score-desc">${humanLabel(hum)}</div>
    </div>
  `;

  // Stat rows
  const tone = r.tone || {};
  document.getElementById('ins-rows').innerHTML = `
    <div class="stat-row"><span class="skey">Sentiment</span><span class="sval"><b>${cap(tone.sentiment)}</b></span></div>
    <div class="stat-row"><span class="skey">Formality</span><span class="sval"><b>${cap(tone.formality)}</b></span></div>
    <div class="stat-row"><span class="skey">Confidence</span><span class="sval"><b>${cap(tone.confidence)}</b></span></div>
  `;

  // Top dense words leaderboard
  const dense = (r.density || []).filter(d => d.level !== 'ok').slice(0, 6);
  if (dense.length) {
    const maxCt = dense[0].count || 1;
    const rows = dense.map(d => {
      const pct   = Math.round((d.count / maxCt) * 100);
      const color = d.level === 'dense' ? '#c96e5c' : '#d4a65e';
      return `
        <div class="lb-row">
          <span class="lb-word">${d.word}</span>
          <div class="lb-bar-bg"><div class="lb-bar" style="width:${pct}%;background:${color}"></div></div>
          <span class="lb-count">×${d.count}</span>
        </div>`;
    }).join('');
    document.getElementById('ins-words').innerHTML = `<div class="lb-label">Overused words</div>${rows}`;
  } else {
    document.getElementById('ins-words').innerHTML = '';
  }
}

function renderAI(r) {
  document.getElementById('ai-empty').style.display  = 'none';
  document.getElementById('ai-data').style.display   = '';

  const pct   = Math.round(r.humanness ?? 50);
  const color = humanColor(pct);

  document.getElementById('ai-score-wrap').innerHTML = `
    <div class="ai-score-card">
      <div class="ai-score-head">
        <span class="ai-score-label">Humanness score</span>
        <span class="ai-score-num" style="color:${color}">${pct}%</span>
      </div>
      <div class="ai-bar-bg"><div class="ai-bar" style="width:${pct}%;background:${color}"></div></div>
      <p class="ai-score-desc">${humanLabel(pct)}</p>
    </div>
  `;

  // Tone chips
  const tone = r.tone || {};
  const chips = [];
  const sentMap = { positive: '', negative: 'warn', neutral: 'neutral' };
  const fmtMap  = { formal: '', casual: 'neutral', unknown: 'neutral' };
  const confMap = { assured: '', hedged: 'warn', unknown: 'neutral' };

  if (tone.sentiment) chips.push({ label: cap(tone.sentiment), cls: sentMap[tone.sentiment] || '' });
  if (tone.formality) chips.push({ label: cap(tone.formality), cls: fmtMap[tone.formality] || '' });
  if (tone.confidence) chips.push({ label: cap(tone.confidence), cls: confMap[tone.confidence] || '' });

  document.getElementById('ai-rows').innerHTML = `
    <div class="tone-chips">
      ${chips.map(c => `<span class="tone-chip ${c.cls}">${c.label}</span>`).join('')}
    </div>
    <div class="stat-rows" style="margin-top:12px">
      <div class="stat-row"><span class="skey">Avg sentence</span><span class="sval"><b>${r.sentences ? Math.round((r.words||0)/r.sentences) : '—'}</b> words</span></div>
      <div class="stat-row"><span class="skey">Words</span><span class="sval"><b>${fmtNum(r.words)}</b></span></div>
      <div class="stat-row"><span class="skey">Readability</span><span class="sval"><b>${r.fleschEase ?? '—'}</b>/100</span></div>
    </div>
  `;
}

// ── Word count for textarea ────────────────────────────────────────────────────

function updateDirectCount(ta, countEl) {
  const words = ta.value.trim() ? ta.value.trim().split(/\s+/).length : 0;
  const chars = ta.value.length;
  countEl.textContent = `${words} word${words !== 1 ? 's' : ''} · ${chars} chars`;
}

// ── Init ──────────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', async () => {
  initTabs();

  const stored = await chrome.storage.local.get([STORAGE_KEY, 'sophia-last-analysis']);
  const s      = stored[STORAGE_KEY] || {};
  let   theme  = s.theme || 'system';

  applyTheme(theme);
  darkQuery.addEventListener('change', () => applyTheme(theme));

  // Greeting
  const firstName = (s.name || '').split(' ')[0];
  const h = new Date().getHours();
  const timeWord = h < 12 ? 'Morning' : h < 18 ? 'Afternoon' : 'Evening';
  const quip = QUIPS[Math.floor(Math.random() * QUIPS.length)];
  document.getElementById('greeting').textContent =
    firstName ? `${timeWord}, ${firstName}. ${quip}` : quip;
  document.getElementById('foot-label').textContent = firstName || 'Sophia';

  // Quick toggles sync from settings
  const qtBubble  = document.getElementById('qt-bubble');
  const qtSpell   = document.getElementById('qt-spelling');
  const qtDensity = document.getElementById('qt-density');
  if (qtBubble)  qtBubble.checked  = !!s.showBubble;
  if (qtSpell)   qtSpell.checked   = s.spelling  !== false;
  if (qtDensity) qtDensity.checked = s.density   !== false;

  // Highlights toggle
  const hlBtn = document.getElementById('btn-highlight');
  hlBtn.setAttribute('aria-pressed', String(!!s.highlightsOn));

  // ── Status ──────────────────────────────────────────────────────────────────
  const statusDot  = document.getElementById('status-dot');
  const statusText = document.getElementById('status-text');
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const blocked = !activeTab || activeTab.url?.startsWith('chrome://') || activeTab.url?.startsWith('chrome-extension://');

  if (blocked) {
    statusText.textContent = "Open any website and Sophia will be ready.";
  } else {
    const ping = await sendToPage({ type: 'PING' });
    if (ping) {
      statusDot.classList.add('active');
      statusText.textContent = ping.selection
        ? `${ping.selection} chars selected — ready to analyze.`
        : 'Active on this page. Select text or paste below.';
    } else {
      statusDot.classList.remove('active');
      statusText.textContent = 'Reload the page to activate Sophia.';
    }
  }

  // ── Load cached analysis ─────────────────────────────────────────────────────
  const cached = stored['sophia-last-analysis'];
  if (cached) {
    renderInsights(cached);
    renderAI(cached);
  } else {
    const live = await sendToPage({ type: 'GET_ANALYSIS' });
    if (live && live.result) {
      renderInsights(live.result);
      renderAI(live.result);
    }
  }

  // ── Direct textarea word count ────────────────────────────────────────────────
  const directTa    = document.getElementById('direct-ta');
  const directCount = document.getElementById('direct-count');
  const analyzeBtn  = document.getElementById('btn-direct-analyze');

  directTa.addEventListener('input', () => updateDirectCount(directTa, directCount));

  // ── Analyze button (direct text) ─────────────────────────────────────────────
  analyzeBtn.addEventListener('click', async () => {
    const text = directTa.value.trim();
    if (!text) return;
    analyzeBtn.disabled = true;
    analyzeBtn.textContent = 'Analyzing…';

    let result = null;
    const resp = await sendToPage({ type: 'ANALYZE_TEXT', text });
    if (resp && resp.result) {
      result = resp.result;
    }

    analyzeBtn.disabled = false;
    analyzeBtn.textContent = 'Analyze →';

    if (result) {
      renderInsights(result);
      renderAI(result);
      switchTab('insights');
    }
  });

  // ── Open panel on page ────────────────────────────────────────────────────────
  document.getElementById('btn-show-panel').addEventListener('click', async () => {
    await sendToPage({ type: 'TRIGGER_ANALYZE' });
    window.close();
  });

  // ── Settings ──────────────────────────────────────────────────────────────────
  document.getElementById('btn-settings').addEventListener('click', () => {
    chrome.runtime.openOptionsPage();
    window.close();
  });
  const footSettingsLink = document.getElementById('foot-settings-link');
  if (footSettingsLink) footSettingsLink.addEventListener('click', (e) => {
    e.preventDefault();
    chrome.runtime.openOptionsPage();
    window.close();
  });

  // ── Theme segmented control (System / Dawn / Dusk) ───────────────────────────
  document.querySelectorAll('.tseg').forEach(btn => {
    btn.addEventListener('click', async () => {
      theme = btn.dataset.theme;
      // Read-modify-write: the drawer and options page edit this same object, so saving
      // the copy read when the popup opened would undo anything they changed since.
      const fresh = (await chrome.storage.local.get(STORAGE_KEY))[STORAGE_KEY] || {};
      fresh.theme = theme;
      s.theme = theme;
      await chrome.storage.local.set({ [STORAGE_KEY]: fresh });
      applyTheme(theme);
    });
  });

  // ── Highlights toggle ─────────────────────────────────────────────────────────
  hlBtn.addEventListener('click', async () => {
    const on = hlBtn.getAttribute('aria-pressed') !== 'true';
    hlBtn.setAttribute('aria-pressed', String(on));
    s.highlightsOn = on;
    await chrome.storage.local.set({ [STORAGE_KEY]: s });
    sendToPage({ type: 'SET_HIGHLIGHTS', on });
  });

  // ── Quick toggles save ────────────────────────────────────────────────────────
  async function saveQuickToggle() {
    s.showBubble = qtBubble?.checked ?? !!s.showBubble;
    s.spelling   = qtSpell?.checked  !== false;
    s.density    = qtDensity?.checked !== false;
    await chrome.storage.local.set({ [STORAGE_KEY]: s });
    sendToPage({ type: 'SET_BUBBLE', show: s.showBubble });
  }
  [qtBubble, qtSpell, qtDensity].forEach(el => el?.addEventListener('change', saveQuickToggle));
});
