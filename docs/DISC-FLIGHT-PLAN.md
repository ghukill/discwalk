# Disc Flight: Design Notes

> **Status (2026-10-11):** the game flies Hummel's equations by default; see [Flight models](#flight-models). Earlier: step 2 landed (flat disc, lift/drag/gyroscopic roll, throw panel, four shotshaper tables). See [ARCHITECTURE.md](ARCHITECTURE.md#flying-discs-flying_discgd-disc_modelgd-throw_panelgd). Since then: follow cam (V), flight paths (P), launch angle from your view, Jolt physics for landings, slicker ground play, warp (Z). Still to do from this plan: wind, forehand, our own coefficient tables.

High-level plan for adding realistic disc golf disc flight to the voxel game (Godot).

## Physics approach

Treat the disc as a rigid body and apply aerodynamic forces every physics tick, rather than simulating real fluid dynamics or real spin.

- **Forces:** lift, drag, and pitching moment. Each is `coefficient × 0.5 × air_density × speed² × disc_area` (moment also × diameter).
- **Coefficients** are functions of **angle of attack**, the angle between the disc plane and the direction of travel.
- **Spin** acts through gyroscopic precession, turning the pitching moment into a slow **roll**. That roll is what produces turn and fade:
  `roll_rate = -M / (omega * (I_xy - I_z))`

## Reference library: shotshaper

[github.com/kegiljarhus/shotshaper](https://github.com/kegiljarhus/shotshaper) is a Python sports projectile simulator focused on disc golf. It's a good one to experiment with, and the disc model in `shotshaper/projectile.py` is ~150 lines.

What it does:
- Tabulated lift, drag, and moment coefficients vs. angle of attack, per disc model (YAML files in `shotshaper/discs/`)
- Roll from the gyroscopic approximation above
- Wind support, including height-varying wind

What it **doesn't** do (vs. Hummel's 2003 6-DOF frisbee model):
- Spin is constant for the whole flight (no decay)
- No wobble: other angular rates are fixed at zero
- No pitch, roll, or spin damping terms

Start with the shotshaper-style model. If flights feel too "on rails," borrow Hummel's damping terms and spin decay later.

## Flight models

Since branch `hummell-equations` the game has two, picked with `--flight=` (default `hummel`). Code: `scripts/disc_model.gd`.

### `hummel` (default)

From Hummel's thesis (*Frisbee Flight Simulation and Throw Biomechanics*, UC Davis 2003): equations 3.6–3.8, Table 3-2, and the MATLAB in Appendix B (`discfltEOM.m`). Axes: x̂ = airflow projected on the disc plane (roll axis), ŷ = x̂ × n (pitch axis, to the right), n = disc normal; p, q, r = angular rates about them (rad/s); `qAd = ½ρv² × area × diameter`.

| Moment | Formula | Coefficient (Hummel, long flight f2302) |
|---|---|---|
| Roll R | `C_Rp p × qAd` | `C_Rp = −0.0125` (wobble damping) |
| Pitch M | `(C_M(α) + C_Mq q) × qAd` | `C_M(α)` from our disc table; `C_Mq = −0.0144` |
| Spin down N | `C_Nr r × qAd` | `C_Nr = −3.41e-5` |

The damping coefficients are **dimensional** (they multiply a rate in rad/s), so spin decays at `C_Nr qAd / I_z`, which goes as v²: ~7 %/s at 24 m/s, ~1 %/s at 10 m/s. A cd1 at 20 m/s goes 104 → 94 rad/s.

Hummel integrates the full Euler equations (6-DOF, with wobble). The game uses the **quasi-steady** version: wobble (nutation at ~2r ≈ 200 rad/s, damped in ~0.25 s) is skipped, and each tick solves `M_perp = I_z r (w × n)` for the precession rates p and q, a 2×2 linear system including both damping terms, then turns n by them. `tools/discs/hummel_reference.py` integrates the full equations (wobble and all, 256 substeps per tick); the game matches it to ~1–3 % (`tools/flight_test.gd`).

What changes versus shotshaper, by size:

1. **Roll rate.** A gyroscope precesses at `M / (I_z r)`. shotshaper uses `M / (ω (I_z − I_xy))`, and a flat disc has `I_z ≈ 2 I_xy`, so shotshaper rolls about **twice** as fast. That is the big one: drives carry further (dd2 at 24 m/s flat: 60 → 86 m, which fits the "~6–7 ft per mph" rule of thumb better), and the understable cd5 barely turns at 20 m/s (−9 → −2 m) but turns hard at 22 m/s (−18 m). Overstable cd1 fades a bit more (11 → 14 m).
2. **Roll damping** `C_Rp` adds a small pitch rate (q ≈ −C_Rp qAd p / (I_z r), ~15 % of the roll rate), so the nose drifts as the disc turns and fades. With `C_Mq` it trims high-speed turn (dd2 24 m/s flat: −32 → −25 m).
3. **Spin decay**: ~10 % per flight, a slightly bigger late fade.

Caveats: Hummel's coefficients were fit to a 175 g Wham-O Frisbee at ~14 m/s, not golf discs at 20–30 m/s. A disc JSON can override them (`CMq`, `CRp`, `CNr`). Hummel's fourth rate term, `C_Rr` (roll moment from spin, a centre-of-pressure offset), is left out: his value and its scaling disagree with Potts & Crowther's, and our CFD tables have no roll-moment data. Hummel's own MATLAB applies the spin-down moment without `qAd` (`Mspin = [0 0 CNr*omegaspin]`); we follow the thesis equations (3.8), which include it.

### `shotshaper`

The original model (below), kept for A/B and so `tools/flight_test.gd` can still check the port against shotshaper's own flights.

**License note:** shotshaper is GPL-3.0. Porting the equations is fine; porting code directly would carry the license into the game.

### Other references
- **Hummel (2003)**, *Frisbee Flight Simulation and Throw Biomechanics*, UC Davis thesis. The canonical full model.
- **Potts & Crowther**: wind tunnel data most frisbee coefficient sets come from.
- **Kamaruddin**: measurements on actual disc golf drivers.

## Godot integration

- Use `RigidBody3D` and apply aero forces in `_integrate_forces()`.
- **Fake the visual spin.** Track spin rate as a plain variable, rotate the mesh visually, and feed the variable into the roll math. Don't make the physics engine spin at 1000+ RPM.
- On first contact with ground or obstacles, turn off aero forces and let normal physics handle skips and rolls (existing block-throwing behavior).

## Features

### Wind
Start with a single static `Vector3`. Subtract it from the disc's velocity before computing forces.

### Discs
Hand-code 3-5 discs with distinctly different flight styles. Map flight numbers onto coefficient curves, starting from a shotshaper baseline table:
- **Speed:** scales drag down; understable behavior only appears near rated speed
- **Glide:** scales lift
- **Turn:** more negative pitching moment at low angle of attack (high-speed turn)
- **Fade:** more positive pitching moment at higher angle of attack / low speed (end-of-flight hook)

Tune by eye until each disc flies roughly as expected.

### Flight path trail
- Record position every physics tick and render it as a trail. Small cubes via `MultiMeshInstance3D` would fit the voxel style.
- Paths persist in the world so the player can walk around and inspect them.
- Keep the last N throws in different colors for comparison.
- Optional: color the trail by speed or spin rate to show where fade kicks in.

## Launch mechanics

UX to be designed separately. These are the inputs the physics needs, mapped to shotshaper parameters:

| Input | shotshaper param | Notes |
|---|---|---|
| Facing direction | `yaw` | Aim |
| Launch angle (up/down) | `pitch` | Direction of the velocity vector |
| Nose tilt | `nose_angle` | Separate from launch angle; the gap between them is "nose up/down" |
| Roll (hyzer/anhyzer) | `roll_angle` | Arguably the most important shot-shaping input |
| Spin rate | `omega` | Could be derived from speed: `omega ≈ 5.2 × speed` (shotshaper's empirical rule), plus an optional "snap" modifier |
| Release speed | `speed` | |

- **Handedness / throw type:** backhand vs. forehand spin in opposite directions, mirroring turn and fade. This can be a sign flip on spin.
