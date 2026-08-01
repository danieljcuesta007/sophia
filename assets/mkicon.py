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


def arc_path(cx, cy, rx, ry, a0, a1):
    """SVG elliptical arc between two parametric angles. Angles in degrees,
    screen convention (0 = +x, 90 = down). Direction comes from the sign of
    (a1 - a0). Elliptical radii let the bowls be wider than they are tall
    without distorting the round caps (a non-uniform scale would)."""
    p0 = (cx + rx * math.cos(math.radians(a0)), cy + ry * math.sin(math.radians(a0)))
    p1 = (cx + rx * math.cos(math.radians(a1)), cy + ry * math.sin(math.radians(a1)))
    span = a1 - a0
    large = 1 if abs(span) > 180 else 0
    sweep = 1 if span > 0 else 0   # SVG sweep 1 = increasing angle (clockwise)
    return (f"M{p0[0]:.1f},{p0[1]:.1f} "
            f"A{rx},{ry} 0 {large} {sweep} {p1[0]:.1f},{p1[1]:.1f}")


# The mark, revision six: the letter S in Cadence's language. Two bowls stacked
# and tangent at the waist give the classical geometric S; each is one thick
# round-capped stroke, and both are trimmed back from the waist so they never
# touch — the crisp gap is the family trait. Upper bowl near-black, lower bowl
# green: one green element, three colours, no gradients.
RX = 176         # bowl half-width — wider than tall, so the S is not a stack
RY = 150         # bowl half-height
W = 76           # stroke weight, Cadence-heavy
TRIM = 15.0      # degrees pulled back from the waist on each bowl
TERMINAL = 26.0  # degrees of open terminal at each end of the S
CX, CY = 512, 512


def emblem():
    # Upper bowl: from the top-right terminal, counter-clockwise over the top
    # and down the left, stopping short of the waist.
    upper = arc_path(CX, CY - RY, RX, RY, -TERMINAL, -270 + TRIM)
    # Lower bowl: 180-degree rotation of the upper — from just past the waist,
    # clockwise down the right and along the bottom to the lower-left terminal.
    lower = arc_path(CX, CY + RY, RX, RY, -90 + TRIM, 180 - TERMINAL)
    return (
        f'<path d="{upper}" fill="none" stroke="{DARK}" stroke-width="{W}" '
        f'stroke-linecap="round"/>'
        f'<path d="{lower}" fill="none" stroke="{INK}" stroke-width="{W}" '
        f'stroke-linecap="round"/>'
    )


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
