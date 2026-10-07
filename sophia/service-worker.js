'use strict';

// Generate the Sophia "S" icon dynamically using OffscreenCanvas.
// This runs once on install/startup so the extension icon shows the serif S
// without needing hand-crafted PNG files.

function setDynamicIcon() {
  const sizes   = [16, 32, 48, 128];
  const imageData = {};

  for (const size of sizes) {
    const canvas = new OffscreenCanvas(size, size);
    const ctx    = canvas.getContext('2d');
    const r      = size / 2;

    // Sage green circle background
    ctx.fillStyle = '#6b7c52';
    ctx.beginPath();
    ctx.arc(r, r, r, 0, Math.PI * 2);
    ctx.fill();

    // Subtle inner highlight ring
    const grad = ctx.createRadialGradient(r * .6, r * .4, 0, r, r, r);
    grad.addColorStop(0, 'rgba(255,255,255,.18)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(r, r, r, 0, Math.PI * 2);
    ctx.fill();

    // Serif S
    const fontSize = Math.round(size * 0.64);
    ctx.fillStyle   = 'rgba(255,255,255,.96)';
    ctx.font        = `${fontSize}px Georgia, "Times New Roman", serif`;
    ctx.textAlign   = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('S', r, r + size * 0.04);

    imageData[size] = ctx.getImageData(0, 0, size, size);
  }

  chrome.action.setIcon({ imageData });
}

chrome.runtime.onInstalled.addListener(setDynamicIcon);
chrome.runtime.onStartup.addListener(setDynamicIcon);
