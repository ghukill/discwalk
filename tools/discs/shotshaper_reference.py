"""Reference flights from shotshaper itself, for tools/flight_test.gd.

    git clone https://github.com/kegiljarhus/shotshaper /tmp/shotshaper
    uv run --with numpy --with scipy --with pyyaml --with matplotlib \\
        python tools/discs/shotshaper_reference.py /tmp/shotshaper

Prints carry (m, along the throw) and drift (m, + = left) for each case,
released 1.3 m up, ending when the disc gets back to ground level. Paste into
REFERENCE in flight_test.gd if you change cases. (Runs shotshaper as an
outside tool; nothing from it ships in the game.)
"""
import sys

import matplotlib
import numpy as np

matplotlib.use("Agg")
sys.path.insert(0, sys.argv[1])
from shotshaper.projectile import DiscGolfDisc  # noqa: E402

# disc, speed (m/s), spin (rad/s), pitch, nose, roll (deg)
CASES = [
    ("dd2", 24.2, 116.8, 15.5, 0.0, 14.7),
    ("dd2", 24.0, 124.8, 10.0, 0.0, 0.0),
    ("dd2", 20.0, 104.0, 10.0, 0.0, -15.0),
    ("cd1", 20.0, 104.0, 10.0, 0.0, 0.0),
    ("cd5", 20.0, 104.0, 10.0, 0.0, 0.0),
    ("fd2", 22.0, 114.4, 8.0, 2.0, 5.0),
]
for name, U, om, pitch, nose, roll in CASES:
    s = DiscGolfDisc(name).shoot(speed=U, omega=om, pitch=pitch, nose_angle=nose,
                                 roll_angle=roll, position=np.array((0, 0, 1.3)))
    x, y, z = s.position
    print(f"[{name!r}, {U}, {om}, {pitch}, {nose}, {roll}] -> carry {x[-1]:.1f}, left {y[-1]:.1f}")
