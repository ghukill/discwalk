"""Convert shotshaper's disc coefficient tables (YAML) into discwalk's disc JSON.

    uv run --with pyyaml python tools/discs/shotshaper_to_json.py /path/to/shotshaper

Writes data/discs/shotshaper/<id>.json. The tables are GPL-3.0 (see
data/discs/shotshaper/LICENSE); this script only reformats them.
"""
import json
import pathlib
import subprocess
import sys

import yaml

LABELS = {
    "cd1": ("Control driver, overstable", "Innova Firebird"),
    "cd5": ("Control driver, understable", "Innova Roadrunner"),
    "dd2": ("Distance driver", ""),
    "fd2": ("Fairway driver, stable", "Innova Teebird"),
}

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(__file__).resolve().parents[2] / "data" / "discs" / "shotshaper"
commit = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"],
                        capture_output=True, text=True).stdout.strip()
for disc_id, (label, like) in LABELS.items():
    d = yaml.safe_load((src / "shotshaper" / "discs" / f"{disc_id}.yaml").read_text())
    doc = {
        "id": disc_id,
        "label": label,
        "modelled_after": like,
        "source": f"shotshaper {commit[:10]} shotshaper/discs/{disc_id}.yaml (CFD)",
        "license": "GPL-3.0",
        "diameter": d["diameter"],
        "J_xy": d["J_xy"],
        "J_z": d["J_z"],
        "alpha": d["alpha"],
        "Cl": d["Cl"],
        "Cd": d["Cd"],
        "Cm": d["Cm"],
    }
    assert len(doc["alpha"]) == len(doc["Cl"]) == len(doc["Cd"]) == len(doc["Cm"])
    (out / f"{disc_id}.json").write_text(json.dumps(doc, indent=1) + "\n")
    print("wrote", out / f"{disc_id}.json")
