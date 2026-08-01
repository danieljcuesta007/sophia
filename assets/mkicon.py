#!/usr/bin/env python3
"""Sophia Write app icon + logo.

A seal for divine wisdom: warm cream paper, a Didot capital S in Sophia's
green (#3F8A4F), a thin antique-gold double ring with laurel sprigs and a
small spark at the crown. Solid colors only — the brand keeps its color in
the paper and its ink solid; no gradients.

Renders SVG-in-HTML at 1024x1024 via headless Chrome, packs an .icns with
iconutil, and writes a standalone logo.svg. No third-party imaging libs.
Portable: no absolute user paths; Chrome located from standard install spots.
"""
import math
import os
import shutil
import subprocess
import sys

OUT = os.path.dirname(os.path.abspath(__file__))

# The Cadence family language: white ground, near-black rounded capsules,
# exactly one green voice. Sophia inverts the accent — the STEM is the green
# element, the leaves are the dark ones.
PAPER = "#FCFCFD"     # white ground, as Cadence
INK = "#3F8A4F"       # the brand green — the stem and the light
DARK = "#2A2E35"      # Cadence's near-black, for the leaves
INK_DEEP = "#B9BEC2"  # neutral hairline edge, as Cadence — never a colored ring

CANVAS = 1024
BODY = 824
N = 5.0


def find_chrome():
    for p in (
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        os.path.expanduser(
            "~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        shutil.which("chromium") or "",
    ):
        if p and os.path.exists(p):
            return p
    sys.exit("Chrome not found — needed to rasterize the SVG")


def squircle_path(size=BODY, cx=CANVAS / 2, cy=CANVAS / 2, steps=720):
    a = size / 2.0
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2 / N), ct) * a
        y = math.copysign(abs(st) ** (2 / N), st) * a
        pts.append(f"{cx + x:.2f},{cy + y:.2f}")
    return "M" + "L".join(pts) + "Z"


def capsule(x, y, angle_deg, length, width, fill):
    """A rounded capsule (Cadence's shape vocabulary) extending from (x, y)
    along `angle_deg` (SVG rotation: 0 = +x, negative = upward)."""
    r = width / 2
    return (
        f'<g transform="translate({x:.1f},{y:.1f}) rotate({angle_deg:.1f})">'
        f'<rect x="0" y="{-r:.1f}" width="{length:.1f}" height="{width:.1f}" '
        f'rx="{r:.1f}" fill="{fill}"/>'
        f"</g>"
    )


# The mark, revision four: the sapling rebuilt in Cadence's capsule language.
# White ground; the STEM is the one green element (Cadence's one green bar,
# turned to grow); near-black capsule leaves; a green dot of light above.
STEM_X = 512
# Tall enough that every branch surfaces below the rounded cap — a branch
# root peeking past the green tip was the audit catch on the first render.
STEM_TOP = 292
STEM_BOTTOM = 716
STEM_W = 66  # Cadence-weight capsules, not hairlines


def emblem():
    parts = []
    # Branches GROW OUT of the stem: each is a thick round-capped quadratic
    # that starts at the stem's centerline with a vertical tangent (the root
    # is hidden under the stem, drawn after), so it emerges from the stem edge
    # flowing upward, then bends outward. The joint reads as growth, not as a
    # shape parked next to another shape. (attach_y, side, scale.)
    branches = [
        (664, -1, 1.00), (576, +1, 0.88),
        (488, -1, 0.76), (404, +1, 0.64),
    ]
    for y, side, s in branches:
        cx = STEM_X                      # root on the centerline
        cy = y
        ctrl = (cx, cy - 96 * s)         # straight up: tangent matches stem
        end = (cx + side * 132 * s, cy - 172 * s)
        parts.append(
            f'<path d="M{cx},{cy} Q{ctrl[0]:.1f},{ctrl[1]:.1f} '
            f'{end[0]:.1f},{end[1]:.1f}" fill="none" stroke="{DARK}" '
            f'stroke-width="{STEM_W - 4}" stroke-linecap="round"/>'
        )
    # The stem: one green capsule, vertical — drawn over the branch roots so
    # each branch surfaces exactly at the stem edge, tangent-smooth.
    parts.append(capsule(STEM_X, STEM_BOTTOM, -90, STEM_BOTTOM - STEM_TOP,
                         STEM_W, INK))
    # The light it grows toward — with the stem, a quiet lowercase i.
    parts.append(f'<circle cx="{STEM_X}" cy="{STEM_TOP - 96}" r="37" fill="{INK}"/>')
    return "".join(parts)


TEMPLATE = """<!doctype html>
<meta charset="utf-8">
<style>html,body{{margin:0;padding:0;background:transparent}}</style>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="0.24"/>
    </filter>
    <clipPath id="clip"><path d="{path}"/></clipPath>
  </defs>
  <g filter="url(#shadow)">
    <path d="{path}" fill="{paper}"/>
  </g>
  <g clip-path="url(#clip)">
    <path d="{path}" fill="none" stroke="{edge}" stroke-opacity="0.18" stroke-width="6"/>
  </g>
  {emblem}
</svg>
"""

LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 1024 1024">
  <circle cx="512" cy="512" r="472" fill="{paper}"/>
  <circle cx="512" cy="512" r="472" fill="none" stroke="{edge}" stroke-opacity="0.25" stroke-width="4"/>
  {emblem}
</svg>
"""

SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]


def main():
    chrome = find_chrome()
    path = squircle_path()
    html = TEMPLATE.format(path=path, paper=PAPER, edge=INK_DEEP, emblem=emblem())
    src = os.path.join(OUT, "icon.html")
    png = os.path.join(OUT, "icon.png")
    with open(src, "w") as f:
        f.write(html)
    with open(os.path.join(OUT, "logo.svg"), "w") as f:
        f.write(LOGO_SVG.format(paper=PAPER, edge=INK_DEEP, emblem=emblem()))

    subprocess.run([
        chrome, "--headless", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--default-background-color=00000000",
        f"--screenshot={png}", "--window-size=1024,1024", "file://" + src,
    ], check=True, capture_output=True)

    iconset = os.path.join(OUT, "Sophia.iconset")
    subprocess.run(["rm", "-rf", iconset], check=True)
    os.makedirs(iconset)
    for px, scale in SIZES:
        target = px * scale
        suffix = f"{px}x{px}" + ("@2x" if scale == 2 else "")
        subprocess.run(
            ["sips", "-z", str(target), str(target), png,
             "--out", os.path.join(iconset, f"icon_{suffix}.png")],
            check=True, capture_output=True)
    icns = os.path.join(OUT, "Sophia.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    os.remove(src)
    print(f"built {icns} ({os.path.getsize(icns)} bytes) + logo.svg + icon.png")


if __name__ == "__main__":
    main()
