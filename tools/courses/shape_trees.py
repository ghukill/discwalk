# /// script
# requires-python = ">=3.10"
# ///
"""Shape a course's trees.json: open the fairways, thin the woods, pick species.

    python3 tools/courses/shape_trees.py data/courses/morley-field \
        --fairway 16 --thin 0.45 --species socal

trees_from_aerial.py guesses WHERE trees are from a photo. It cannot know
where the holes are, so it drops trees down the middle of mown fairways, and
it has only one idea of what a tree looks like. This takes its output and
makes it a course:

- --fairway R clears a corridor R metres either side of every tee->basket
  line (tapering in near the tee, where you actually stand). A parkland
  course is a mown lane with trees at its edges, not a wood with a hole in
  it. Lone specimens are kept: one tree in the fairway is the shot.
- --thin drops that share of what is left in the woods, lone trees all kept.
- --species assigns kind/form/leaf per tree, so a course can be eucalyptus
  and jacaranda rather than Michigan oak.

Writes trees.json in place (keep the original under git).
"""
import argparse
import json
import math
import pathlib
import random

# Species sets. leaf indexes course.json's "foliage": {"leaves": [...]}.
# share is the share of trees; form/kind bias what they look like.
SPECIES = {
    "socal": [
        # Balboa Park: jacarandas over the fairways, eucalyptus on the
        # skyline, pepper and olive filling in. Low and wide, not forest oak.
        {"name": "jacaranda", "share": 0.42, "leaf": 0, "crown": (3.0, 7.0),
         "forms": ["spreading", "spreading", "forked", "leaning"],
         "kinds": ["big", "big", "medium"]},
        {"name": "eucalyptus", "share": 0.24, "leaf": 1, "crown": (3.0, 6.0),
         "forms": ["eucalyptus"], "kinds": ["giant", "big"]},
        {"name": "pepper", "share": 0.22, "leaf": 2, "crown": (2.5, 5.5),
         "forms": ["leaning", "spreading", "forked"], "kinds": ["big", "medium"]},
        {"name": "olive", "share": 0.09, "leaf": 3, "crown": (2.0, 4.0),
         "forms": ["forked", "spreading"], "kinds": ["medium"]},
        {"name": "palm", "share": 0.03, "leaf": 4, "crown": (2.0, 3.2),
         "forms": ["palm"], "kinds": ["big", "medium"]},
    ],
}


def dist_to_segment(p, a, b):
    ax, az = a
    bx, bz = b
    px, pz = p
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz)), t


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir", type=pathlib.Path)
    ap.add_argument("--fairway", type=float, default=0.0,
                    help="clear this many metres either side of each hole's line")
    ap.add_argument("--tee-clear", type=float, default=7.0,
                    help="always clear this radius round a tee pad")
    ap.add_argument("--keep-specimens", type=float, default=0.06,
                    help="share of fairway trees to keep as lone specimens")
    ap.add_argument("--thin", type=float, default=0.0,
                    help="share of the remaining woods to drop (0..1)")
    ap.add_argument("--species", choices=sorted(SPECIES), default=None)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()

    course = json.loads((a.dir / "course.json").read_text())
    tpath = a.dir / course.get("trees", "trees.json")
    trees = json.loads(tpath.read_text())
    rng = random.Random(a.seed)
    n0 = len(trees)

    lines = [(tuple(h["tee"]), tuple(h["basket"])) for h in course["holes"]]

    kept = []
    cleared = teed = 0
    for t in trees:
        p = tuple(t["at"])
        drop = False
        for tee, basket in lines:
            d, along = dist_to_segment(p, tee, basket)
            if math.hypot(p[0] - tee[0], p[1] - tee[1]) <= a.tee_clear:
                drop = True                      # you stand here
                teed += 1
                break
            if a.fairway > 0.0:
                # Taper: narrow at the tee, full width down the fairway, so a
                # hole opens out rather than being a tunnel of equal width.
                w = a.fairway * (0.45 + 0.55 * min(1.0, along * 2.5))
                if d <= w and rng.random() > a.keep_specimens:
                    drop = True
                    cleared += 1
                    break
        if not drop:
            kept.append(t)

    # Thin what is left in the woods. A tree with no close neighbour is a
    # specimen and stays whatever happens: those are the ones you play around.
    if a.thin > 0.0:
        pts = [tuple(t["at"]) for t in kept]
        out = []
        for i, t in enumerate(kept):
            near = 0
            for j, q in enumerate(pts):
                if i != j and math.dist(pts[i], q) < 9.0:
                    near += 1
                    if near >= 3:
                        break
            if near >= 3 and rng.random() < a.thin:
                continue
            out.append(t)
        thinned = len(kept) - len(out)
        kept = out
    else:
        thinned = 0

    if a.species:
        table = SPECIES[a.species]
        for t in kept:
            r = rng.random()
            acc = 0.0
            sp = table[-1]
            for s in table:
                acc += s["share"]
                if r <= acc:
                    sp = s
                    break
            t["kind"] = rng.choice(sp["kinds"])
            t["form"] = rng.choice(sp["forms"])
            t["leaf"] = sp["leaf"]
            lo, hi = sp["crown"]
            t["crown"] = round(min(max(t.get("crown", 3.0), lo), hi), 2)

    tpath.write_text(json.dumps(kept, separators=(",", ":")) + "\n")
    size = course["size"]
    ha = size[0] * size[1] / 10000.0
    print("%s: %d -> %d trees (%.1f/ha)" % (a.dir.name, n0, len(kept), len(kept) / ha))
    print("  cleared %d from fairways, %d round tees, thinned %d from woods"
          % (cleared, teed, thinned))
    if a.species:
        counts = {}
        for t in kept:
            counts[t["form"]] = counts.get(t["form"], 0) + 1
        print("  forms: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))


if __name__ == "__main__":
    main()
