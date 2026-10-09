# Disc tables

Each disc is one JSON file, `data/discs/<source>/<id>.json`. The game loads
every file under here (`DiscModel.load_all()` in `scripts/disc_model.gd`) and
lists them in the throw panel.

```json
{
 "id": "dd2", "label": "Distance driver", "source": "...", "license": "...",
 "diameter": 0.211,            // m
 "J_xy": 0.003755,             // inertia across the disc, per kg (m^2)
 "J_z": 0.007465,              // inertia about the spin axis, per kg (m^2)
 "alpha": [-90, ..., 90],      // angle of attack (deg), ascending
 "Cl": [...], "Cd": [...], "Cm": [...]   // lift, drag, pitching moment
}
```

Beyond ±90° the model mirrors the table (an upside-down disc).

## shotshaper/ (GPL-3.0, borrowed for now)

`cd1` (overstable control driver), `cd5` (understable control driver),
`dd2` (distance driver) and `fd2` (stable fairway driver) are CFD tables from
[shotshaper](https://github.com/kegiljarhus/shotshaper) (commit `c99e7a511b`),
converted by `tools/discs/shotshaper_to_json.py`. They are **GPL-3.0**; see
`shotshaper/LICENSE`. No shotshaper code is in the game, only these numbers.

## Swapping them out

To replace them with our own tables (e.g. built from the Potts & Crowther
wind-tunnel curves, or tuned from flight numbers):

1. Add `data/discs/discwalk/<id>.json` files in the same format.
2. Delete `data/discs/shotshaper/`.
3. In `tools/flight_test.gd`, drop the shotshaper `REFERENCE` cases (or swap
   in reference numbers for the new tables). The "character" checks (overstable
   fades, understable turns, forehand mirrors backhand, hyzer bends) refer to
   disc ids `cd1`, `cd5`, `fd2`: point them at the new discs.
4. `grep -rn shotshaper` should then only hit the docs.
