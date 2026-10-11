"""Build discwalk's disc tables: data/discs/discwalk/<id>.json.

    python3 tools/discs/build_tables.py

Every number's provenance is in docs/PHYSICS.md. In short, for each disc:

1. -5..15 deg: Kamaruddin (2011) wind-tunnel data for the real disc it is
   inspired by (tools/discs/kamaruddin_2011.py): C_L from the linear fit,
   C_D and C_M digitized curves.
2. Just outside that (to ~25 deg, ~-12 deg): the measured trends continued.
   C_L linear, C_D parabolic about its minimum, C_M with its end slope easing
   off (it can't keep climbing: CFD and Potts & Crowther level off by ~30 deg).
3. Far outside (stalled, up to +-90 deg): a low-aspect-ratio flat plate.
   Normal force C_N = 1.17 sqrt|sin a| (Hoerner: a round plate face-on has
   C_D ~1.17, and low-aspect-ratio plates reach most of it soon after stall),
   C_L = C_N cos a, C_D = C_D,min + C_N |sin a|, and C_M = k C_N cos a: the
   centre of pressure starts at the disc's measured aerodynamic centre
   (k, Table 5.7) and slides to the middle as a -> 90.
4. Steps 2 and 3 are blended with a smoothstep over 25..45 deg (and
   -12..-30 deg), so the table is continuous and smooth.

Inertia comes from the measured rim geometry (Table 4.1) with a two-part mass
model (flight plate + rim), see inertia(). Mass 175 g for all.
"""
import json
import math
import pathlib

import kamaruddin_2011 as K

OUT = pathlib.Path(__file__).resolve().parents[2] / "data" / "discs" / "discwalk"
MASS = 0.175           # kg (game uses one mass for all discs)
PLATE_T = 0.002        # m, flight-plate thickness (assumed)
RIM_FILL = 0.6         # rim cross-section as a fraction of width x thickness (assumed)
C_N90 = 1.17           # round flat plate, face on (Hoerner, Fluid-Dynamic Drag)
POS_BLEND = (25.0, 45.0)
NEG_BLEND = (-12.0, -30.0)
CM_EASE_POS = 10.0     # deg: how quickly the C_M slope eases off past 15 deg
CM_EASE_NEG = 5.0      # deg: ... and past -5 deg

# alpha grid for the output table: fine where flights live, coarse in the stall
GRID = ([-90, -80, -70, -60, -50, -40, -35, -30, -25, -20, -16, -14, -12, -10, -8, -6]
        + list(range(-5, 16)) + [17, 19, 21, 23, 25, 28, 31, 35, 40, 45, 50, 60, 70, 80, 90])

# Our discs. Glacial names (Michigan's landscape is all of these). "src" is the
# Kamaruddin disc whose data we use. Ordered putter -> mids -> drivers, the
# drivers from understable to overstable. "kind" follows the rim: the drivers'
# rims are 2.1-2.3 cm wide (Table 4.1), distance-driver territory (the Storm's
# isn't given; it is a driver in the thesis). "stability" describes how each
# flies in the game (docs/PHYSICS.md); both show in the throw HUD. (A disc may set "cm_shift" to offset
# C_M and "synthetic": True, for a disc no one has measured; none do yet.)
DISCS = [
    dict(id="kettle", label="Kettle", order=1, src="Aviar", kind="putter", stability="straight",
         note="A kettle is the hole a buried ice block leaves: where the disc ends up."),
    dict(id="drumlin", label="Drumlin", order=2, src="Roc", kind="midrange", stability="stable",
         note="A drumlin is a smooth hill the ice streamlined: steady, with a gentle fade."),
    dict(id="esker", label="Esker", order=3, src="Buzz", kind="midrange", stability="straight",
         note="An esker is a long, straight ridge left by a river under the ice."),
    dict(id="till", label="Till", order=4, src="Quarter K", kind="distance driver", stability="very understable",
         note="Till is the jumble the glacier drops: very understable, a hyzer-flip disc."),
    dict(id="outwash", label="Outwash", order=5, src="Storm", kind="distance driver", stability="understable",
         note="Outwash plains spread out from the ice: an easy, slightly understable driver."),
    dict(id="moraine", label="Moraine", order=6, src="Wraith", kind="distance driver", stability="stable",
         note="The big ridge at the edge of the ice: the long distance driver."),
    dict(id="erratic", label="Erratic", order=7, src="Flick", kind="distance driver", stability="very overstable",
         note="An erratic is a boulder the ice dropped somewhere odd. Very overstable: always hooks."),
]


def lerp(xs, ys, x):
    for i in range(1, len(xs)):
        if x <= xs[i]:
            t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
    return ys[-1]


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def measured(src):
    """Measured -5..15 curves for a Kamaruddin disc: (cl, cd, cm) lists."""
    cl0, cla, cd0, _, _, _ = K.FITS[src]
    cl = [cl0 + cla * a for a in K.ALPHA]
    cm = K.CM[src]
    if src in K.CD:
        cd = K.CD[src]
    elif src == "Buzz":       # Roc's curve, shifted by the C_D_0 difference
        off = cd0 - K.FITS["Roc"][2]
        cd = [c + off for c in K.CD["Roc"]]
    else:                     # drivers: Wraith's curve, shifted (see module doc)
        w0, w15 = K.FITS["Wraith"][2], K.CD["Wraith"][-1]
        lo, hi = cd0 - w0, K.CD15[src] - w15
        cd = [c + lo + (hi - lo) * min(max(a / 15.0, 0.0), 1.0)
              for a, c in zip(K.ALPHA, K.CD["Wraith"])]
    return cl, cd, cm


def slope(xs, ys, x0, x1):
    """Least-squares slope of ys over x0..x1."""
    pts = [(x, y) for x, y in zip(xs, ys) if x0 <= x <= x1]
    mx = sum(p[0] for p in pts) / len(pts)
    my = sum(p[1] for p in pts) / len(pts)
    return sum((x - mx) * (y - my) for x, y in pts) / sum((x - mx) ** 2 for x, _ in pts)


def table(src, cm_shift=0.0):
    A = K.ALPHA
    cl, cd, cm = measured(src)
    cm = [c + cm_shift for c in cm]
    cl0, cla = K.FITS[src][0], K.FITS[src][1]
    k_ac = K.AERO_CENTRE[src]
    # drag: parabola about the minimum, fitted to the upper half of the data
    i_min = min(range(len(A)), key=lambda i: cd[i])
    a_min, cd_min = A[i_min], cd[i_min]
    upper = [(a, c) for a, c in zip(A, cd) if a >= 5]
    k_cd = (sum((c - cd_min) * (a - a_min) ** 2 for a, c in upper)
            / sum((a - a_min) ** 4 for a, _ in upper))
    s_pos = slope(A, cm, 12, 15)
    s_neg = slope(A, cm, -5, -2)

    def extended(a):
        """Measured data, or its trend continued just outside -5..15."""
        if -5 <= a <= 15:
            return lerp(A, cl, a), lerp(A, cd, a), lerp(A, cm, a)
        l = cl0 + cla * a
        if a > 15:
            d = cd[-1] + k_cd * ((a - a_min) ** 2 - (15 - a_min) ** 2)
            m = cm[-1] + s_pos * CM_EASE_POS * (1 - math.exp(-(a - 15) / CM_EASE_POS))
        else:
            d = cd[0] + k_cd * ((a - a_min) ** 2 - (-5 - a_min) ** 2)
            m = cm[0] - s_neg * CM_EASE_NEG * (1 - math.exp(-(-5 - a) / CM_EASE_NEG))
        return l, d, m

    def stalled(a):
        r = math.radians(a)
        s, c = math.sin(r), math.cos(r)
        cn = C_N90 * math.copysign(math.sqrt(abs(s)), s)
        return cn * c, cd_min + abs(cn * s), k_ac * cn * c

    rows = []
    for a in GRID:
        e = extended(a)
        w = smoothstep(*POS_BLEND, a) if a > 15 else smoothstep(-NEG_BLEND[0], -NEG_BLEND[1], -a) if a < -5 else 0.0
        f = stalled(a)
        rows.append([a] + [round((1 - w) * x + w * y, 4) for x, y in zip(e, f)])
    return rows


def inertia(g):
    """Per-kg inertia (J_xy, J_z) from rim geometry: flight plate + rim ring."""
    R, ri, t = g["d"] / 2, g["d_in"] / 2, g["t"]
    v_plate = math.pi * ri * ri * PLATE_T
    v_rim = 2 * math.pi * (R + ri) / 2 * RIM_FILL * g["rim_w"] * t
    fp = v_plate / (v_plate + v_rim)
    fr = 1 - fp
    jz = fp * ri * ri / 2 + fr * (R * R + ri * ri) / 2
    jxy = fp * ri * ri / 4 + fr * ((R * R + ri * ri) / 4 + t * t / 12)
    return jxy, jz


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.json"):
        f.unlink()
    for d in DISCS:
        src = d["src"]
        # Storm has no geometry in Table 4.1: use the Wraith's (same class)
        g = K.GEOMETRY.get(src, K.GEOMETRY["Wraith"])
        jxy, jz = inertia(g)
        rows = table(src, d.get("cm_shift", 0.0))
        synthetic = d.get("synthetic", False)
        out = {
            "id": d["id"],
            "label": d["label"],
            "order": d["order"],
            "kind": d["kind"],
            "stability": d["stability"],
            "inspired_by": ("synthetic: %s's data, C_M shifted %+.3f" % (src, d["cm_shift"]))
            if synthetic else ("%s %s" % (g["maker"], src) if src in K.GEOMETRY else "%s (maker not given in the thesis)" % src),
            "note": d["note"],
            "source": "Kamaruddin 2011 (wind tunnel, %s) + discwalk extension; "
                      "tools/discs/build_tables.py, docs/PHYSICS.md" % src,
            "license": "same as discwalk",
            "diameter": g["d"],
            "J_xy": round(jxy, 6),
            "J_z": round(jz, 6),
            "alpha": [r[0] for r in rows],
            "Cl": [r[1] for r in rows],
            "Cd": [r[2] for r in rows],
            "Cm": [r[3] for r in rows],
        }
        (OUT / f"{d['id']}.json").write_text(json.dumps(out, indent=1) + "\n")
        print(f"{d['id']:8s} <- {out['inspired_by']:32s} J_xy={jxy:.5f} J_z={jz:.5f}")


if __name__ == "__main__":
    main()
