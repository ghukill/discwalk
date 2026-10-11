"""Reference flights for the Hummel model, for tools/flight_test.gd.

    uv run --with numpy python tools/discs/hummel_reference.py

The game's Hummel model (scripts/disc_model.gd) is quasi-steady: it solves for
the steady precession each tick and skips the wobble. This script is the check
on that shortcut: a FULL rigid-body attitude integration from Hummel's Euler
equations (thesis Appendix B, discfltEOM.m, rewritten in vector form), wobble
and all, with fine substeps. Same disc tables, same damping coefficients, same
60 Hz translation step as the game.

State: velocity v, disc normal n, cross-axis angular velocity w (perpendicular
to n), signed spin r about n. With H = I_xy w + I_z r n and dH/dt = M:
    I_z dr/dt = N                                  (spin down)
    I_xy dw/dt = M_perp - I_z r (w x n)            (precession + wobble)
    dn/dt = w x n
Moments (Hummel eq. 3.6-3.8), x = airflow in the disc plane, y = x cross n:
    R = C_Rp p qAd,  M = (C_M(alpha) + C_Mq q) qAd,  N = C_Nr r qAd.

Prints carry (m, along the throw) and drift (m, + = left) per case, released
1.3 m up, ending when the disc gets back to ground level. Paste into
HUMMEL_REFERENCE in flight_test.gd if you change cases or coefficients.
"""
import json
import math
import pathlib

import numpy as np

RHO, G, MASS = 1.225, 9.8, 0.175
CMQ, CRP, CNR = -1.44e-2, -1.25e-2, -3.41e-5      # Hummel long flight f2302
SUB = 256                                         # attitude substeps per 60 Hz tick
DISCS = pathlib.Path(__file__).resolve().parents[2] / "data" / "discs" / "discwalk"

# disc, speed (m/s), spin (rad/s), pitch, nose, roll (deg)
# (spin = 5.2 x speed, the game's auto spin). All RH backhand.
CASES = [
    ("moraine", 24.0, 124.8, 10.0, 0.0, 10.0),   # distance driver, hyzer flip
    ("moraine", 24.0, 124.8, 10.0, 0.0, 0.0),    # ... flat: turns
    ("erratic", 24.0, 124.8, 10.0, 0.0, 0.0),    # overstable: fades anyway
    ("till", 23.0, 119.6, 10.0, 0.0, 25.0),      # very understable: needs hyzer
    ("outwash", 23.0, 119.6, 10.0, 0.0, 15.0),
    ("esker", 19.0, 98.8, 10.0, 0.0, 10.0),
    ("drumlin", 19.0, 98.8, 10.0, 0.0, 10.0),
    ("kettle", 16.0, 83.2, 10.0, 0.0, 0.0),      # putter
]


def load(name):
    d = json.loads((DISCS / f"{name}.json").read_text())
    d["area"] = math.pi * d["diameter"] ** 2 / 4
    d["Iz"], d["Ixy"] = MASS * d["J_z"], MASS * d["J_xy"]
    d["a"] = np.array(d["alpha"], float)
    return d


def coeffs(d, a):
    """Lift, drag, moment at angle of attack a (deg); mirrored past +-90."""
    a = (a + 180) % 360 - 180
    s = 1.0
    if a > 90:
        a, s = 180 - a, -1.0
    elif a < -90:
        a, s = -180 - a, -1.0
    return (s * np.interp(a, d["a"], d["Cl"]), np.interp(a, d["a"], d["Cd"]),
            s * np.interp(a, d["a"], d["Cm"]))


def rot(v, axis, ang):
    axis = axis / np.linalg.norm(axis)
    return (v * math.cos(ang) + np.cross(axis, v) * math.sin(ang)
            + axis * axis.dot(v) * (1 - math.cos(ang)))


def launch(speed, pitch, nose, roll, hand):
    """Same as DiscModel.launch_state, throwing along -Z (Godot forward)."""
    fwd, up = np.array([0, 0, -1.0]), np.array([0, 1.0, 0])
    p = math.radians(pitch)
    right = np.cross(fwd, up)
    vel = (fwd * math.cos(p) + up * math.sin(p)) * speed
    n = rot(up, right, p + math.radians(nose))
    n = rot(n, vel / np.linalg.norm(vel), -math.radians(roll) * hand)
    return vel, n / np.linalg.norm(n)


def fly(name, speed, spin, pitch, nose, roll, hand=1.0):
    d = load(name)
    dt, h = 1 / 60, 1 / 60 / SUB
    v, n = launch(speed, pitch, nose, roll, hand)
    pos = np.array([0, 1.3, 0.0])
    r, w = -hand * spin, np.zeros(3)        # released with no wobble
    iz, ixy, ad = d["Iz"], d["Ixy"], d["area"] * d["diameter"]
    t = 0.0
    while pos[1] > 0 and t < 30:
        sp = np.linalg.norm(v)
        vh = v / sp
        vn = v.dot(n)
        alpha = math.degrees(math.atan2(-vn, np.linalg.norm(v - n * vn)))
        cl, cd, _ = coeffs(d, alpha)
        lift = n - vh * n.dot(vh)
        force = (lift / np.linalg.norm(lift) * cl - vh * cd) * 0.5 * RHO * sp * sp * d["area"]
        for _ in range(SUB):
            vn = v.dot(n)
            vp = v - n * vn
            x = vp / np.linalg.norm(vp)
            y = np.cross(x, n)
            cm = coeffs(d, math.degrees(math.atan2(-vn, np.linalg.norm(vp))))[2]
            qad = 0.5 * RHO * sp * sp * ad
            moment = x * (CRP * w.dot(x)) * qad + y * (cm + CMQ * w.dot(y)) * qad
            # dw/dt = (I_z r / I_xy)(n x w) + M_perp / I_xy: rotate exactly, then push
            w = rot(w, n, iz * r / ixy * h) + (moment - n * moment.dot(n)) / ixy * h
            wl = np.linalg.norm(w)
            if wl > 1e-12:
                n = rot(n, w, wl * h)
                n /= np.linalg.norm(n)
            w -= n * w.dot(n)
            r += CNR * r * qad / iz * h
        v = v + (force / MASS + np.array([0, -G, 0])) * dt
        pos = pos + v * dt
        t += dt
    return -pos[2], -pos[0], abs(r)


if __name__ == "__main__":
    for c in CASES:
        carry, left, spin = fly(*c)
        print(f"\t[{list(c)!r}, [{carry:.1f}, {left:.1f}]],   # spin {c[2]:.0f} -> {spin:.0f}"
              .replace("'", '"'))
