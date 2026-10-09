# Disc Flight: Design Notes

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
