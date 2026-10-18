# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Guess a course's trees from its aerial photo (site_from_geo.py's aerial.png).

    uv run tools/courses/trees_from_aerial.py data/courses/ponds-at-lakeshore
    uv run tools/courses/trees_from_aerial.py <dir> --preview /tmp/trees.png

Writes <dir>/trees.json: [{"at": [x, z], "crown": r, "kind", "form"}, ...] in
course metres (docs/COURSE_FORMAT.md), which course.json points at with
"trees": "trees.json". --preview draws the guesses over the photo.

How: on a summer photo of mown grass, trees and their shadows are the dark
things. Each dark blob is a crown plus its shadow, cast away from the sun, so:

- A small blob is one tree. Its crown is at the sunward end; the blob's width
  across the shadow is the crown's width, and a long shadow for its width
  means a tall, narrow tree (the photo's spruces and pines come out "tall").
- A big blob is a wood or a grove. Trim a few metres off its shadow side, then
  pack crowns into what's left, biggest first.

This is a starting point for an agent or a person to edit, not a survey: it
misses some saplings and merges trees that touch.
"""
import argparse
import json
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

PX = 2.0                     # aerial pixels per metre
DARK = 0.40                  # luminance (0..1) under which it's tree or shadow
GREEN = 0.05                 # 2g - r - b over which a darker pixel is leaves
SINGLE_MAX = 220.0           # m²: blobs up to this are one tree
TRIM = 4.0                   # m trimmed off a grove's shadow side
CROWN_MIN, CROWN_MAX = 1.4, 7.0
GROVE_MIN = 2.0              # m: smallest crown packed into a grove
LEAFY = 0.04                 # share of green pixels a crown needs (else: a building's shadow)
KINDS = [(2.4, "sapling"), (4.2, "medium"), (6.0, "big"), (99, "giant")]


def sun_away(dark):
    """The shadow axis (x, z), as a unit vector: the long axis of the small
    blobs, since a lone tree's blob is stretched along its shadow. Which way
    along it is the caller's job (sunlit leaves are at the sunward end)."""
    lab, n = nd.label(dark)
    cov = np.zeros((2, 2))
    for sl in nd.find_objects(lab):
        ys, xs = np.nonzero(lab[sl] == lab[sl][lab[sl] > 0][0])
        if 40 < len(xs) < SINGLE_MAX * PX * PX:
            c = np.cov(np.vstack([xs, ys]))
            if np.isfinite(c).all():
                cov += c
    w, v = np.linalg.eigh(cov)
    return v[:, 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir", type=pathlib.Path)
    ap.add_argument("--preview", type=pathlib.Path)
    a = ap.parse_args()

    photo = Image.open(a.dir / "aerial.png").convert("RGB")
    im = nd.uniform_filter(np.asarray(photo).astype(float) / 255, size=(3, 3, 1))
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    lum = (r + g + b) / 3
    green = (lum < 0.45) & (2 * g - r - b > GREEN)
    dark = nd.binary_opening((lum < DARK) | green, iterations=1)

    axis = sun_away(dark)
    # Sign: from the green (sunlit leaves) toward the rest of the blob.
    lab, n = nd.label(dark)
    votes = 0.0
    for i, sl in enumerate(nd.find_objects(lab), 1):
        m = lab[sl] == i
        if not (40 < m.sum() < SINGLE_MAX * PX * PX):
            continue
        ys, xs = np.nonzero(m)
        gy, gx = np.nonzero(m & green[sl])
        if len(gx):
            votes += np.dot([xs.mean() - gx.mean(), ys.mean() - gy.mean()], axis)
    s = axis if votes > 0 else -axis
    print(f"shadows fall toward ({s[0]:+.2f}, {s[1]:+.2f})")

    trees = []
    perp = np.array([-s[1], s[0]])
    for i, sl in enumerate(nd.find_objects(lab), 1):
        m = lab[sl] == i
        area = m.sum() / (PX * PX)
        if area < 3.0:
            continue
        ys, xs = np.nonzero(m)
        xs = xs + sl[1].start + 0.5
        ys = ys + sl[0].start + 0.5
        if area <= SINGLE_MAX:
            along = xs * s[0] + ys * s[1]
            across = xs * perp[0] + ys * perp[1]
            length = (along.max() - along.min()) / PX
            # Width near the sunward end (the crown), not the shadow's tail.
            near = along < along.min() + max(4.0, 0.4 * (along.max() - along.min()))
            width = (across[near].max() - across[near].min()) / PX
            crown = float(np.clip(width / 2, CROWN_MIN, CROWN_MAX))
            a0 = along.min() / PX + crown
            c0 = (across[near].max() + across[near].min()) / 2 / PX
            x, z = a0 * s + c0 * perp
            tall = length > 3.2 * width
            trees.append((x, z, crown, tall, False))
        else:
            # Grove: trim the shadow side, then pack crowns biggest first.
            pad = int(CROWN_MAX * PX) + 2
            y0, x0 = max(0, sl[0].start - pad), max(0, sl[1].start - pad)
            sub = lab[y0:sl[0].stop + pad, x0:sl[1].stop + pad] == i
            k = int(round(TRIM * PX))
            shifted = nd.shift(sub.astype(float), (-s[1] * k, -s[0] * k), order=0) > 0.5
            core = sub & shifted
            dist = nd.distance_transform_edt(core) / PX
            yy, xx = np.mgrid[0:core.shape[0], 0:core.shape[1]]
            while True:
                j = np.argmax(dist)
                d = dist.flat[j]
                if d < GROVE_MIN / 1.15:
                    break
                cy, cx = divmod(j, core.shape[1])
                crown = float(min(d * 1.15, CROWN_MAX))
                trees.append(((x0 + cx + 0.5) / PX, (y0 + cy + 0.5) / PX, crown, False, True))
                dist[(xx - cx) ** 2 + (yy - cy) ** 2 < (crown * 1.6 * PX) ** 2] = 0

    # Roofs and building shadows are dark too, but never green.
    yy, xx = np.mgrid[0:lum.shape[0], 0:lum.shape[1]]
    leafy = []
    for t in trees:
        x, z, crown = t[0] * PX, t[1] * PX, t[2] * PX
        x0, x1 = int(max(0, x - crown)), int(min(lum.shape[1], x + crown + 1))
        z0, z1 = int(max(0, z - crown)), int(min(lum.shape[0], z + crown + 1))
        disc = (xx[z0:z1, x0:x1] - x) ** 2 + (yy[z0:z1, x0:x1] - z) ** 2 <= crown * crown
        if disc.any() and green[z0:z1, x0:x1][disc].mean() >= LEAFY:
            leafy.append(t)
    print(f"{len(trees) - len(leafy)} dark spots dropped as not leafy")
    trees = leafy

    out = []
    for k, (x, z, crown, tall, grove) in enumerate(sorted(trees, key=lambda t: (t[1], t[0]))):
        kind = next(name for lim, name in KINDS if crown < lim)
        if kind == "sapling":
            form = "sapling"
        elif tall or grove and k % 3 == 0:
            form = "tall"
        else:
            form = ["spreading", "forked", "leaning", "spreading"][k % 4]
        out.append({"at": [round(float(x), 1), round(float(z), 1)], "crown": round(crown, 1),
                    "kind": kind, "form": form})
    (a.dir / "trees.json").write_text("[\n" + ",\n".join(json.dumps(t) for t in out) + "\n]\n")
    print(f"trees.json: {len(out)} trees")

    if a.preview:
        d = ImageDraw.Draw(photo)
        for t in out:
            x, z = t["at"][0] * PX, t["at"][1] * PX
            rr = t["crown"] * PX
            d.ellipse([x - rr, z - rr, x + rr, z + rr], outline=(255, 60, 200) if t["form"] == "tall"
                      else (60, 255, 80), width=2)
        photo.save(a.preview)


if __name__ == "__main__":
    main()
