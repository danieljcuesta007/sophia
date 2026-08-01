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

PAPER = "#101711"     # near-black with a green cast — modern tech ground
INK = "#54B368"       # Sophia green, lifted to glow on the dark ground
INK_DEEP = "#3F8A4F"  # the brand green proper (edges, hairlines)
GOLD = "#D9AE52"      # gold, brightened for dark ground — the bud and spark

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


def leaf(x, y, angle_deg, length=54, width=20, fill=GOLD):
    """A pointed laurel leaf: two quadratic arcs base->tip, rotated in place."""
    return (
        f'<path d="M0,0 Q{width / 2:.1f},{-length / 2:.1f} 0,{-length} '
        f'Q{-width / 2:.1f},{-length / 2:.1f} 0,0 Z" fill="{fill}" '
        f'transform="translate({x:.1f},{y:.1f}) rotate({angle_deg:.1f})"/>'
    )


def laurel(side):
    """One sprig: a stem arcing up the lower quarter of the ring, leaves
    alternating along it. side=-1 left, +1 right."""
    r = 268  # stem radius, inside the inner ring
    cx, cy = 512, 512
    parts = []
    # Stem: arc from near bottom-center up to ~48 degrees on this side.
    a0, a1 = math.radians(96), math.radians(38)
    p0 = (cx + side * r * math.sin(a1), cy + r * math.cos(a1))
    p1 = (cx + side * r * math.sin(a0), cy + r * math.cos(a0))
    parts.append(
        f'<path d="M{p1[0]:.1f},{p1[1]:.1f} A{r},{r} 0 0 {1 if side > 0 else 0} '
        f'{p0[0]:.1f},{p0[1]:.1f}" fill="none" stroke="{GOLD}" '
        f'stroke-width="9" stroke-linecap="round"/>'
    )
    # Paired leaves hugging the stem — a real sprig, not thorns. Each node has
    # an outer and an inner leaf leaning up the stem's direction of travel.
    for i in range(4):
        a = math.radians(86 - i * 15)
        lx = cx + side * r * math.sin(a)
        ly = cy + r * math.cos(a)
        # Stem tangent at this node, pointing "up the sprig".
        tangent = -side * (90 - math.degrees(a))
        scale = 1.0 - i * 0.08
        parts.append(leaf(lx, ly, tangent - side * 30,
                          length=62 * scale, width=24 * scale))
        parts.append(leaf(lx, ly, tangent + side * 34,
                          length=52 * scale, width=21 * scale))
    # Tip leaf pointing along the stem's end.
    a_tip = math.radians(34)
    tx = cx + side * r * math.sin(a_tip)
    ty = cy + r * math.cos(a_tip)
    parts.append(leaf(tx, ty, -side * (90 - math.degrees(a_tip)),
                      length=56, width=20))
    return "".join(parts)


def spark():
    """A small four-point star hovering above the bud — the light it grows
    toward."""
    cx, cy, R, r = 496, 178, 34, 10.5
    pts = []
    for i in range(8):
        rad = R if i % 2 == 0 else r
        a = math.pi / 4 * i - math.pi / 2
        pts.append(f"{cx + rad * math.cos(a):.1f},{cy + rad * math.sin(a):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{GOLD}"/>'


def bezier(p0, p1, p2, p3, t):
    """Point and tangent angle (deg) on a cubic at t."""
    u = 1 - t
    x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
    y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
    dx = 3 * u**2 * (p1[0] - p0[0]) + 6 * u * t * (p2[0] - p1[0]) + 3 * t**2 * (p3[0] - p2[0])
    dy = 3 * u**2 * (p1[1] - p0[1]) + 6 * u * t * (p2[1] - p1[1]) + 3 * t**2 * (p3[1] - p2[1])
    return x, y, math.degrees(math.atan2(dy, dx))


def veined_leaf(x, y, angle_deg, length, width):
    """A leaf with a paper vein down its center — botanical, not thorn-like."""
    return (
        f'<g transform="translate({x:.1f},{y:.1f}) rotate({angle_deg:.1f})">'
        f'<path d="M0,0 Q{width / 2:.1f},{-length * 0.52:.1f} 0,{-length:.1f} '
        f'Q{-width / 2:.1f},{-length * 0.52:.1f} 0,0 Z" fill="{INK}"/>'
        f'<path d="M0,{-length * 0.12:.1f} L0,{-length * 0.82:.1f}" '
        f'stroke="{PAPER}" stroke-width="5" stroke-linecap="round" opacity="0.85"/>'
        f"</g>"
    )


# The sapling: an upright stem with a whisper of an S in its sway — growth,
# not serpent. One cubic bottom-to-tip; leaves in near-pairs; a gold bud crown.
STEM = ((540, 706), (462, 600), (562, 452), (506, 332))


def branch():
    parts = []
    p0, p1, p2, p3 = STEM
    parts.append(
        f'<path d="M{p0[0]},{p0[1]} C{p1[0]},{p1[1]} {p2[0]},{p2[1]} {p3[0]},{p3[1]}" '
        f'fill="none" stroke="{INK}" stroke-width="26" stroke-linecap="round"/>'
    )
    # Leaf nodes: (t along stem, side, scale). Pairs are slightly staggered the
    # way real phyllotaxis is; sizes taper toward the crown.
    nodes = [
        (0.16, -1, 1.00), (0.24, +1, 0.96),
        (0.42, -1, 0.92), (0.50, +1, 0.88),
        (0.66, -1, 0.76), (0.74, +1, 0.68),
    ]
    for t, side, scale in nodes:
        x, y, ang = bezier(p0, p1, p2, p3, t)
        # How far the stem leans off vertical here (moving tip-ward means
        # dy < 0, so a vertical stem reports -90).
        lean = ang + 90
        tilt = lean + side * 56  # leaves reach up and well outward
        parts.append(veined_leaf(x, y, tilt, length=132 * scale, width=60 * scale))
    # The bud crowning the tip — gold, the divine touch as part of the growth.
    # Nearly vertical regardless of the stem's final lean: a bud reaches for
    # the light, and it must not collide with the crown leaves.
    tx, ty, tang = bezier(p0, p1, p2, p3, 1.0)
    # Tip-ward travel reports ~-90 when vertical; damp only the deviation.
    lean = (tang + 90) * 0.35
    parts.append(
        f'<g transform="translate({tx:.1f},{ty:.1f}) rotate({lean:.1f})">'
        f'<path d="M0,12 Q30,-34 0,-92 Q-30,-34 0,12 Z" fill="{GOLD}"/>'
        f"</g>"
    )
    return "".join(parts)


def emblem():
    """The mark: sapling and spark on the dark ground. No rings, no frame —
    ornament is what made revision two feel antique. Scaled about the group's
    own center (~505, 448) so the plant owns the field."""
    return (
        '<g transform="translate(512,512) scale(1.16) translate(-505,-448)">'
        + spark() + branch() + "</g>"
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
