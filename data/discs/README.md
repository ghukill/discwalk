# Disc tables

Each disc is one JSON file, `data/discs/<source>/<id>.json`. The game loads
every file under here (`DiscModel.load_all()` in `scripts/disc_model.gd`),
sorts them by `order` and lists them in the throw HUD (Tab).

```json
{
 "id": "moraine", "label": "Moraine",    // label is what the HUD shows
 "order": 6, "kind": "distance driver",   // optional: sort key; kind shows in the HUD
 "stability": "stable",                   // optional: shows in the HUD next to kind
 "inspired_by": "Innova Wraith",          // optional: the real disc behind the data
 "source": "...", "license": "...",
 "diameter": 0.211,                       // m
 "J_xy": 0.00375,                         // inertia across the disc, per kg (m^2)
 "J_z": 0.00747,                          // inertia about the spin axis, per kg (m^2)
 "alpha": [-90, ..., 90],                 // angle of attack (deg), ascending
 "Cl": [...], "Cd": [...], "Cm": [...],   // lift, drag, pitching moment
 "CMq": -0.0144, "CRp": -0.0125, "CNr": -3.41e-5  // optional: Hummel damping (per rad/s)
}
```

Beyond ±90° the model mirrors the table (an upside-down disc). Without the
three damping terms a disc uses Hummel's (2003) values (`HUMMEL_*` in
`scripts/disc_model.gd`).

## discwalk/ (ours)

Seven discs built from Kamaruddin's (2011) wind-tunnel measurements of real
golf discs, by `tools/discs/build_tables.py`. **Don't edit the JSON by hand**:
change the builder (or `tools/discs/kamaruddin_2011.py`) and rerun

```sh
python3 tools/discs/build_tables.py
```

| id | Kind | Data from |
|---|---|---|
| kettle | putter | Innova Aviar |
| drumlin | midrange | Innova Roc |
| esker | midrange | Discraft Buzz |
| till | distance driver | Discwing Quarter K |
| outwash | distance driver | "Storm" (maker not given in the thesis) |
| moraine | distance driver | Innova Wraith |
| erratic | distance driver | Discraft Flick |

How the tables are made, and why: [docs/PHYSICS.md](../../docs/PHYSICS.md).
After changing them, refresh the reference flights in `tools/flight_test.gd`
(see docs/DEVELOPMENT.md).
