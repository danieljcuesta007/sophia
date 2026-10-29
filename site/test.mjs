import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir, access } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const pages = { 'index.html': await readFile('index.html', 'utf8'), 'legal.html': await readFile('legal.html', 'utf8') };
const home = pages['index.html'], legal = pages['legal.html'], html = home + legal;
const css = await readFile('style.css', 'utf8');
const js = await readFile('site.js', 'utf8');
const headers = await readFile('_headers', 'utf8');
const ART = (await readdir('art')).filter(f => f.endsWith('.svg')).sort().map(f => `art/${f}`);
const SHIPPED = ['index.html', 'legal.html', 'style.css', 'site.js', 'favicon.png', 'apple-touch-icon.png', 'icon-512.png', '_headers', ...ART];
const OUTBOUND = /^https:\/\/(github\.com\/danieljcuesta007\/(sophia|cadence)(\/|#|$)|danielcuesta007\.com$|addisuna\.com$|skeptic\.pages\.dev$|cadence-dictation\.pages\.dev$|www\.grammarly\.com\/(plans|privacy-policy)$|languagetool\.org\/premium$|github\.com\/languagetool-org\/languagetool$|support\.apple\.com\/)/;
const README = await readFile('../README.md', 'utf8');

test('internal links and fragments resolve, IDs are unique per page', () => {
  for (const [name, page] of Object.entries(pages)) {
    const ids = [...page.matchAll(/\sid="([^"]+)"/g)].map(m => m[1]);
    assert.equal(new Set(ids).size, ids.length, name);
    for (const [, href] of page.matchAll(/<a\b[^>]*href="([^"]+)"/g)) {
      if (/^https?:/.test(href)) continue;
      const [file, fragment] = href.split('#');
      assert.ok(!file || pages[file], href);
      if (fragment) assert.ok(pages[file || name].includes(`id="${fragment}"`), `${name}: ${href}`);
    }
  }
  for (const id of ['features', 'mac', 'compare', 'get', 'creator', 'faq', 'why-unpacked']) assert.ok(home.includes(`id="${id}"`), id);
  for (const id of ['privacy', 'license', 'credits', 'trademarks', 'contact']) assert.ok(legal.includes(`id="${id}"`), id);
});

test('links into the repo README point at headings that exist', () => {
  const anchors = new Set([...README.matchAll(/^#+ (.+)$/gm)].map(m => m[1].toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-')));
  for (const [, frag] of html.matchAll(/href="https:\/\/github\.com\/danieljcuesta007\/sophia#([^"]+)"/g)) assert.ok(anchors.has(frag), `README has no #${frag}`);
});

test('local assets exist and nothing loads from another origin', async () => {
  for (const [, ref] of html.matchAll(/(?:src|href)="([^"#:]+\.(?:css|js|png|svg))"/g)) await access(ref);
  assert.doesNotMatch(html, /<(?:script|link|img|iframe)\b[^>]*(?:src|href)="https?:/);
  for (const [, href] of html.matchAll(/<a\b[^>]*href="(https?:[^"]+)"/g)) assert.match(href, OUTBOUND, href);
  assert.doesNotMatch(js, /fetch\s*\(|XMLHttpRequest|sendBeacon|WebSocket|localStorage|sessionStorage|https?:\/\//);
});

test('markup works under the strict content security policy', () => {
  for (const rule of ["default-src 'none'", "script-src 'self'", "style-src 'self'", "connect-src 'none'", "form-action 'none'", "frame-ancestors 'none'"]) assert.ok(headers.includes(rule), rule);
  assert.doesNotMatch(html, /\sstyle="/);
  assert.doesNotMatch(html, /\son[a-z]+="/);
  assert.doesNotMatch(html, /<script\b(?![^>]*\bsrc=)[^>]*>/);
  assert.doesNotMatch(html, /<form\b/);
});

test('each page has one h1, a skip link and labelled navigation', () => {
  for (const page of Object.values(pages)) {
    assert.equal((page.match(/<h1\b/g) || []).length, 1);
    assert.match(page, /class="skip" href="#main"/);
    assert.match(page, /id="main" tabindex="-1"/);
    assert.match(page, /aria-label="Main navigation"/);
    for (const [img] of page.matchAll(/<img\b[^>]*>/g)) assert.match(img, /\salt="/, img);
  }
  assert.match(css, /prefers-reduced-motion:reduce/);
  assert.match(css, /prefers-color-scheme:dark/);
  assert.match(css, /min-height:44px/);
  assert.match(home, /class="demo" aria-hidden="true"/, 'the animated demo is decoration, hidden from screen readers');
});

// Honest about the release state: the Chrome extension installs today, the Mac app does not yet.
test('the site never promises a Mac download that does not exist', () => {
  assert.match(home, /There's no download yet/);
  assert.match(home, /In development/);
  assert.doesNotMatch(html, /\.dmg|brew install|Download for Mac|notarized|App Store|Web Store listing/i);
  assert.match(home, /href="https:\/\/github\.com\/danieljcuesta007\/sophia\/archive\/refs\/heads\/main\.zip"/);
  for (const step of ['chrome://extensions', 'Developer mode', 'Load unpacked', 'extension › sophia']) assert.ok(home.includes(step), step);
});

test('privacy claims match on every page, including the one outbound font request', () => {
  assert.match(home, /Google Fonts/); assert.match(legal, /Google Fonts/);
  assert.match(legal, /no networking code/); assert.match(home, /never leaves your Mac/);
  for (const page of Object.values(pages)) assert.match(page, /not affiliated with/);
});

test('comparison is dated, sourced and fair', () => {
  const section = home.match(/<section class="compare"[\s\S]*?<\/section>/)[0];
  assert.match(section, /as of October 2026/);
  for (const source of ['grammarly.com/plans', 'grammarly.com/privacy-policy', 'languagetool.org/premium', 'languagetool-org/languagetool', 'support.apple.com']) assert.ok(section.includes(source), source);
  assert.match(section, /Where they win/);
  assert.match(home, /og:image" content="https:\/\//);
});

test('site.js: copy writes the command; no clipboard hides the button', async () => {
  const copy = { textContent: 'Copy', dataset: { copy: 'git clone x' }, listeners: {}, addEventListener(t, f) { this.listeners[t] = f; } };
  const status = { textContent: '' }; const written = [];
  runInNewContext(js, { getSelection: () => ({ selectAllChildren() {} }), document: { querySelector: () => status, querySelectorAll: s => s === '[data-copy]' ? [copy] : [] },
    navigator: { clipboard: { writeText: async t => { written.push(t); } } }, setTimeout() {}, clearTimeout() {} });
  await copy.listeners.click();
  assert.deepEqual(written, ['git clone x']); assert.equal(copy.textContent, 'Copied'); assert.equal(status.textContent, 'Copied to clipboard');
  const lone = { dataset: { copy: 'x' }, remove() { this.removed = true; } };
  runInNewContext(js, { document: { querySelector: () => null, querySelectorAll: s => s === '[data-copy]' ? [lone] : [] }, navigator: {}, setTimeout() {}, clearTimeout() {} });
  assert.equal(lone.removed, true);
  assert.equal(home.match(/data-copy="([^"]+)"/)[1], home.match(/<pre><code>([^<]+)<\/code><\/pre>/)[1], 'the copy button copies exactly the command shown');
});

test('two copy buttons share the status line without wiping each other', async () => {
  const timers = [];
  const mk = () => ({ textContent: 'Copy', dataset: { copy: 'x' }, listeners: {}, addEventListener(t, f) { this.listeners[t] = f; } });
  const a = mk(), b = mk(); const status = { textContent: '' };
  let fail = false;
  runInNewContext(js, { getSelection: () => ({ selectAllChildren() {} }), document: { querySelector: () => status, querySelectorAll: s => s === '[data-copy]' ? [a, b] : [] },
    navigator: { clipboard: { writeText: async () => { if (fail) throw new Error('denied'); } } }, setTimeout: fn => timers.push(fn), clearTimeout() {} });
  await a.listeners.click();
  fail = true; await b.listeners.click();
  const said = status.textContent;
  timers[0]();  // A's reset fires after B spoke
  assert.equal(a.textContent, 'Copy'); assert.equal(status.textContent, said, "B's message survives A's reset");
  timers[1]();  // B's own reset clears B's message
  assert.equal(status.textContent, '', 'no stale result left behind');
  // Same result from two buttons in a row: A's older timer must not clear B's newer message.
  fail = false; timers.length = 0;
  await a.listeners.click(); await b.listeners.click(); await b.listeners.click(); // the text cycles back to A's exact string
  const newest = status.textContent;
  timers[0]();
  assert.equal(status.textContent, newest, "A's timer leaves B's identical, newer message alone");
  timers[2](); assert.equal(status.textContent, '', "B's latest timer clears it");
});

test('the page has the status line copy results are announced in', () => {
  const tags = home.match(/<[^>]*data-copy-status[^>]*>/g) || [];
  assert.equal(tags.length, 1, 'exactly one status line');
  assert.match(tags[0], /role="status"/);
  assert.match(tags[0], /class="visually-hidden"/, 'the status line must stay invisible');
});

test('copy degrades: no selection API gives an honest message; no status line keeps the buttons', async () => {
  const copy = { textContent: 'Copy', dataset: { copy: 'x' }, listeners: {}, previousElementSibling: { tagName: 'PRE' }, addEventListener(t, f) { this.listeners[t] = f; }, remove() { this.removed = true; } };
  const status = { textContent: '' };
  runInNewContext(js, { getSelection: () => { throw new Error('no selection here'); }, document: { querySelector: () => status, querySelectorAll: s => s === '[data-copy]' ? [copy] : [] },
    navigator: { clipboard: { writeText: async () => { throw new Error('denied'); } } }, setTimeout() {}, clearTimeout() {} });
  await copy.listeners.click();
  assert.equal(copy.textContent, 'Copy failed'); assert.match(status.textContent, /copy the command manually/); assert.doesNotMatch(status.textContent, /above|selected/);
  const kept = { textContent: 'Copy', dataset: { copy: 'x' }, listeners: {}, addEventListener(t, f) { this.listeners[t] = f; }, remove() { this.removed = true; } };
  runInNewContext(js, { document: { querySelector: () => null, querySelectorAll: s => s === '[data-copy]' ? [kept] : [] }, navigator: { clipboard: { writeText: async () => {} } }, setTimeout() {}, clearTimeout() {} });
  await kept.listeners.click();
  assert.equal(kept.removed, undefined); assert.equal(kept.textContent, 'Copied');
  const lost = { textContent: 'Copy', dataset: { copy: 'x' }, listeners: {}, addEventListener(t, f) { this.listeners[t] = f; } };
  runInNewContext(js, { document: { querySelector: () => null, querySelectorAll: s => s === '[data-copy]' ? [lost] : [] }, navigator: { clipboard: { writeText: async () => { throw new Error('denied'); } } }, setTimeout() {}, clearTimeout() {} });
  await lost.listeners.click();
  assert.equal(lost.textContent, 'Copy failed', 'a failure without a status line still shows on the button');
});

test('build ships exactly the reviewed files, unchanged and free of private data', async () => {
  const builtFiles = (await readdir('dist', { recursive: true })).filter(f => f !== 'art');
  assert.deepEqual(builtFiles.sort(), [...SHIPPED].sort());
  for (const file of SHIPPED) {
    const built = await readFile(`dist/${file}`), source = await readFile(file);
    assert.ok(built.equals(source), file);
    if (/\.(html|css|js|svg)$|_headers/.test(file)) assert.doesNotMatch(built.toString(), /\/Users\/|\/private\/tmp\/|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|@nd\.edu|@gmail/);
  }
});

test('the content cap tracks the window instead of stopping at a fixed width', () => {
  for (const [bp, cap] of [['1300', '1400px'], ['1800', '1640px'], ['2400', '1840px']]) {
    assert.ok(css.includes(`@media (min-width:${bp}px) { :root { --max:min(${cap}, calc(100vw - 2 * var(--gutter))); } }`), bp);
  }
  assert.match(css, /main > section > \* \{ max-width:var\(--max\)/);
});

test('the art is self-contained, described, used, and in Sophia colours only', async () => {
  const palette = ['#FFFFFF', '#FCFCFD', '#B9BEC2', '#3F8A4F', '#DDDBD0', '#C4C2B7', '#83817A', '#F6F6F5', '#14140F', '#A14B3C', '#3F5D78', '#76845E', 'NONE'];
  for (const file of ART) {
    const svg = await readFile(file, 'utf8');
    assert.match(svg, /<title id="t">[^<]{12,}<\/title>/, `${file} describes itself`);
    assert.doesNotMatch(svg, /<script|\sstyle=|<style|\son[a-z]+=|https?:\/\/(?!www\.w3\.org\/2000\/svg)/, file);
    for (const [, paint] of svg.matchAll(/\b(?:fill|stroke)="([^"]+)"/g)) assert.ok(palette.includes(paint.toUpperCase()), `${file}: ${paint}`);
  }
  for (const file of ART) assert.ok(home.includes(`src="${file}"`), `${file} is on the home page`);
  assert.ok(legal.includes('src="art/mark.svg"'));
  assert.doesNotMatch(html + css, /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u, 'no emoji anywhere');
});

test('every page says Sophia is a preview still in development', () => {
  for (const [name, page] of Object.entries(pages)) assert.match(page, /class="preview-note"[^>]*>[\s\S]*?still in development/, name);
  assert.match(README, /^> \*\*Preview\.\*\* Sophia is still in development/m);
});

// 29 Oct: one credit line for every DC Labs product, and never "with Claude".
test('every page credits "Built by DC Labs, a Daniel J. Cuesta company"', async () => {
  const home = await readFile('index.html', 'utf8'), legal = await readFile('legal.html', 'utf8');
  assert.match(home, /<h2 id="creator-title">Built by DC Labs, a Daniel J\. Cuesta company\.<\/h2>/);
  for (const page of [home, legal]) {
    assert.match(page, /<strong>Sophia<\/strong><br>Built by DC Labs, a Daniel J\. Cuesta company\./);
    assert.doesNotMatch(page, /with(&nbsp;|\s)Claude\b(?! Code)/);
  }
});
