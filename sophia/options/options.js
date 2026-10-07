'use strict';

const STORAGE_KEY = 'sophia-settings';

// Theme is 'system' (the default when unset), 'dawn' or 'dusk'; system follows the OS.
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
let currentTheme = 'system';

function applyThemeToPage(theme) {
  currentTheme = theme || 'system';
  const dusk = currentTheme === 'dusk' || (currentTheme === 'system' && darkQuery.matches);
  if (dusk) document.body.setAttribute('data-theme', 'dark');
  else document.body.removeAttribute('data-theme');
}
darkQuery.addEventListener('change', () => applyThemeToPage(currentTheme));

async function loadSettings() {
  const stored = await chrome.storage.local.get(STORAGE_KEY);
  const s = stored[STORAGE_KEY] || {};

  if (s.name) {
    document.getElementById('name-input').value = s.name;
    document.getElementById('intro-line').textContent = `Good to see you again, ${s.name}.`;
  }

  const theme = s.theme || 'system';
  const radio = document.querySelector(`input[name="theme"][value="${theme}"]`);
  if (radio) radio.checked = true;
  else {
    const sys = document.querySelector('input[name="theme"][value="system"]');
    if (sys) sys.checked = true;
  }
  applyThemeToPage(theme);

  document.getElementById('toggle-bubble').checked    = !!s.showBubble;
  document.getElementById('toggle-spelling').checked  = s.spelling    !== false;
  document.getElementById('toggle-grammar').checked   = s.grammar     !== false;
  document.getElementById('toggle-density').checked   = s.density     !== false;
  document.getElementById('toggle-readability').checked = s.readability !== false;
}

async function saveSettings() {
  const theme = (document.querySelector('input[name="theme"]:checked') || {}).value || 'system';

  // Read-modify-write. The in-page drawer edits the same object, so writing
  // a fresh literal here would silently drop any key this page doesn't own.
  const stored = await chrome.storage.local.get(STORAGE_KEY);
  const s = Object.assign({}, stored[STORAGE_KEY] || {}, {
    name:        document.getElementById('name-input').value.trim(),
    theme,
    showBubble:  document.getElementById('toggle-bubble').checked,
    spelling:    document.getElementById('toggle-spelling').checked,
    grammar:     document.getElementById('toggle-grammar').checked,
    density:     document.getElementById('toggle-density').checked,
    readability: document.getElementById('toggle-readability').checked,
  });

  await chrome.storage.local.set({ [STORAGE_KEY]: s });
  applyThemeToPage(s.theme);

  if (s.name) {
    document.getElementById('intro-line').textContent = `Good to see you again, ${s.name}.`;
  }

  // Flash subtle saved indicator
  const msg = document.getElementById('saved-msg');
  if (msg) {
    msg.classList.add('show');
    clearTimeout(msg._t);
    msg._t = setTimeout(() => msg.classList.remove('show'), 1800);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  loadSettings();

  // ── Auto-save on any toggle/radio change ──────────────────────────────
  document.querySelectorAll('input[type="radio"], input[type="checkbox"]').forEach(el => {
    el.addEventListener('change', () => {
      // Immediately preview theme change before saving
      if (el.name === 'theme') applyThemeToPage(el.value);
      saveSettings();
    });
  });

  // ── Auto-save name with debounce ──────────────────────────────────────
  let nameTimer;
  document.getElementById('name-input').addEventListener('input', () => {
    clearTimeout(nameTimer);
    nameTimer = setTimeout(() => saveSettings(), 700);
  });

  // ── Keep Save button as fallback (optional click) ────────────────────
  const saveBtn = document.getElementById('save-btn');
  if (saveBtn) saveBtn.addEventListener('click', saveSettings);
});
