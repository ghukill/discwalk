# The physics of discwalk, and why

This is the rationale for the flight model: what is simulated, which equations
and numbers we use, where each comes from, and what we assumed. The approach is
deliberately **cherry-picked**: the best available equations (Hummel 2003) plus
the best available measurements of real golf discs (Kamaruddin 2011), joined by
a few simple, stated physical assumptions where no data exists.

Code: `scripts/disc_model.gd` (the maths), `scripts/flying_disc.gd` (the body in
the world), `tools/discs/` (how the disc tables are made and checked).

## At a glance: where every number comes from

| What | Value / form | Source | Confidence |
|---|---|---|---|
| Equations of motion (forces, moments, gyroscopic precession, spin down) | see [Equations](#equations) | Hummel 2003, eq. 3.4–3.8 and Appendix B (`discfltEOM.m`) | high: rigid-body physics |
| Lift `C_L(α)`, −5..15° | linear fit per disc | Kamaruddin 2011, Table 5.6 (wind tunnel) | high |
| Drag `C_D(α)`, −5..15° | digitized curves | Kamaruddin 2011, Figs. 5.9–5.11 | good (±0.005; some discs derived, see below) |
| Pitching moment `C_M(α)`, −5..15° | digitized curves | Kamaruddin 2011, Figs. 5.9–5.12 | good (±0.003; Buzz ±0.005) |
| Coefficients beyond −5..15° | measured trend continued, then a stalled flat plate | our model, cross-checked against Potts & Crowther (to 30°) and CFD (Giljarhus 2022) | fair: few flights get there |
| Aerodynamic centre per disc | 5–21 % of the diameter ahead of centre | Kamaruddin 2011, Table 5.7 | high |
| Disc geometry (diameter, rim) | per disc | Kamaruddin 2011, Table 4.1 | high |
| Moments of inertia | plate + rim model | ours, from Table 4.1 geometry; lands on ~0.0075 kg·m²/kg like 3D-scanned discs (Giljarhus 2022) | good |
| Mass | 175 g, all discs | typical max-weight disc | — |
| Pitch damping `C_Mq` | −0.0144 /(rad/s) | Hummel 2003, Table 3-2 (long flight f2302) | fair: measured on a Frisbee |
| Roll damping `C_Rp` | −0.0125 /(rad/s) | Hummel 2003, Table 3-2 | fair: Frisbee; the one that matters most |
| Spin down `C_Nr` | −3.41e-5 /(rad/s) | Hummel 2003, Table 3-2 | fair: Frisbee; small effect |
| Roll moment from spin `C_Rr` | 0 (left out) | Kamaruddin measured ~0 rolling moment; Hummel's and Potts & Crowther's values disagree | — |
| Spin at release | 5.2 rad/s per m/s | linear fit to measured throws (Giljarhus 2022 / shotshaper notes) | fair |
| Air density | 1.225 kg/m³ | sea level, 15 °C | — |

## Equations

The disc is a rigid body. Each physics tick (60 Hz) with air velocity **v**
(disc velocity minus wind), disc normal **n** (out of the top face) and spin
`r` (signed about **n**):

- **Angle of attack** `α` = angle between the airflow and the disc plane,
  positive when air hits the underside.
- **Forces:** lift `L = C_L(α) ½ρv²A` perpendicular to the airflow (in the
  plane of airflow and normal), drag `D = C_D(α) ½ρv²A` against it, plus
  gravity. `A` = planform area.
- **Moments** (Hummel eq. 3.6–3.8), with axes x̂ = airflow projected on the
  disc plane (roll), ŷ = x̂ × **n** (pitch, to the right), and rates p, q about
  them, `qAd = ½ρv²·A·d`:
  - roll `R = C_Rp·p·qAd`
  - pitch `M = (C_M(α) + C_Mq·q)·qAd`
  - spin down `N = C_Nr·r·qAd`
- **Gyroscope.** A spinning disc doesn't simply pitch up under `M`: its
  angular momentum `H = I_z r n` precesses. Hummel integrates the full Euler
  equations, `I_xy dω/dt + I_z r (ω × n) = M_⊥`. The `I_xy dω/dt` term is
  wobble (nutation), which spins at about `2r` (~200 rad/s) and which Hummel's
  damping kills within ~0.25 s. We drop it and keep the **steady precession**
  `M_⊥ = I_z r (ω × n)`: two linear equations for p and q, solved exactly
  every tick (`DiscModel._attitude()`). Without damping, the roll rate is
  `p = M / (I_z r)`: the textbook gyroscope. That slow roll is **turn**
  (early, fast, nose-down moment) and **fade** (late, slow, nose-up moment).
- **Spin down:** `I_z dr/dt = N`, an exponential decay at
  `C_Nr·qAd / I_z`: ~7 %/s at 24 m/s, ~1 %/s at 10 m/s. A long drive loses
  ~15 % of its spin; slower spin means a bit more fade at the end.
- **Landing:** on first contact with anything the aerodynamics switch off for
  good and the physics engine takes over (skips, rolls, flops). A
  simplification: a skipping disc really is still flying a little.

**Is the shortcut OK?** `tools/discs/hummel_reference.py` integrates the
*full* equations (wobble and all, 256 substeps per tick) for the same throws;
the game lands within ~1–3 % (checked every run of `tools/flight_test.gd`).

## The discs

Seven discs, each built from the wind-tunnel data of one real disc. Names are
Michigan glacial landforms. Drivers are listed from understable to overstable.

| Disc | Kind | Data from | Character (in game) | `C_M` at 0° | aero centre |
|---|---|---|---|---|---|
| **Kettle** | putter | Innova Aviar | short and straight at putting speed (16 m/s: 37 m) | −0.018 | 5 % |
| **Drumlin** | midrange | Innova Roc | steady, fades with a little hyzer | −0.014 | 7 % |
| **Esker** | midrange | Discraft Buzz | straight-to-understable; likes some hyzer | −0.034 | 10 % |
| **Till** | driver | Discwing Quarter K | very understable: turns over flat, needs 20–30° hyzer (hyzer flip) | −0.038 | 13 % |
| **Outwash** | driver | "Storm" (maker not given) | slightly understable; long with 15–20° hyzer (~86 m at 23 m/s) | −0.026 | 9 % |
| **Moraine** | driver | Innova Wraith | the distance driver: 10° hyzer at 24 m/s flips up and goes ~93 m | −0.020 | 15 % |
| **Erratic** | driver | Discraft Flick | very overstable: fades left even thrown anhyzer | −0.007 | 21 % |

How to read the last two columns: a more negative `C_M` at low angle of attack
means more **turn** at speed (understable); an aerodynamic centre further
ahead of the middle means `C_M` climbs faster with α, so more **fade** as the
disc slows (overstable). Kamaruddin (Table 5.7) found exactly this ordering:
putter mildest, Flick the most nose-up.

Numbers are RH backhand, 10° launch, auto spin, carry to first contact on flat
ground (ground play adds more). "Left" = fade side.

## How a disc table is built

`tools/discs/build_tables.py` writes `data/discs/discwalk/<id>.json` (α from
−90 to 90°; the game mirrors beyond that for an upside-down disc).

1. **Measured, −5..15°.** Kamaruddin's data for the source disc
   (`tools/discs/kamaruddin_2011.py`). Wind tunnel, non-spinning discs (spin
   barely changes the loads: Potts 2005), Reynolds number 3.78×10⁵ = 22–27 m/s,
   so real throwing speeds. Pitching moment is about the disc centre.
   - `C_L`: the Table 5.6 linear fit (every disc's lift is a straight line here).
   - `C_M`, `C_D`: digitized by eye from the thesis figures at 400 dpi with a
     1° × 0.01 grid overlaid. The Buzz `C_M` was read from the crowded Fig. 5.12
     and agrees with Table 5.6 (trim at 8°).
   - Not digitized, because the curves overlap within reading precision:
     Buzz `C_D` = Roc's curve shifted by their `C_D,0` difference; Flick,
     Storm and Quarter K `C_D` = Wraith's curve shifted by the `C_D,0`
     difference at low α, tapering to the difference read at 15°.
2. **Trend continued, just outside.** `C_L` stays linear; `C_D` follows a
   parabola about its minimum (fitted to 5..15°); `C_M` keeps its end slope but
   eases off (it cannot climb forever: Potts & Crowther's Frisbee data and the
   CFD tables both level off by ~30°).
3. **Stalled flat plate, far outside.** Normal force `C_N = 1.17·√|sin α|`:
   a round plate face-on has `C_D ≈ 1.17` (Hoerner), and low-aspect-ratio plates
   reach most of it soon after stall. Then `C_L = C_N cos α`,
   `C_D = C_D,min + C_N |sin α|`, and `C_M = k·C_N cos α`, where `k` is the
   disc's measured aerodynamic-centre offset: the centre of pressure starts
   there and slides to the middle as α → 90°.
4. **Blend** 2 into 3 with a smoothstep over 25..45° (and −12..−30°), so the
   table is continuous.

Cross-checks at 30° (the edge of most flights): our `C_L` 1.15–1.35, `C_D`
0.63–0.77, `C_M` 0.08–0.19 versus Potts & Crowther's Frisbee 1.68 / 0.92 / 0.11
and Giljarhus's CFD drivers 1.3–1.8 / 0.74–0.81 / 0.15–0.17. Same ballpark;
ours stall a little earlier.

**Inertia.** From Table 4.1 geometry: a flight plate (2 mm thick, across the
inside rim diameter) plus a rim ring (rim width × disc thickness × 0.6 fill),
same plastic, scaled to the disc mass. Drivers come out at
`J_z ≈ 0.0074–0.0080` m² (per kg), like the 3D-scanned discs in Giljarhus 2022;
putters and mids slightly higher (wider plate). The result barely depends on
the two assumed numbers (±5 % across plausible values). The Storm has no
geometry in the thesis: it uses the Wraith's.

## Launch

- Spin defaults to 5.2 rad/s per m/s of release speed (~1200 rpm at 24 m/s),
  a linear fit to measured throws; you can unlock and set it.
- A RH backhand spins clockwise seen from above; a forehand is the mirror
  image (turn and fade swap sides).
- Release: velocity at the launch angle (your view pitch), the disc tipped
  back with it plus any nose angle, then banked by hyzer/anhyzer about the
  flight path.

## Validation

- **Maths:** game vs full 6-DOF Hummel integration, 8 throws covering all 7
  discs, within 5 % carry / 2.5 m drift (`tools/flight_test.gd`).
- **Character:** the checks in `tools/flight_test.gd` (Erratic fades from
  anhyzer, Till turns over flat, Moraine hyzer-flips long, Kettle is short and
  straight, forehand mirrors backhand, more hyzer bends more, spin bleeds off).
- **Real-world sanity:** distance per speed. A Moraine at 20 m/s (45 mph)
  carries ~66 m flat and at 24 m/s (54 mph) ~93 m with a little hyzer, before
  ground play. That is in the range players quote for those arm speeds, but we
  have no measured throws of our own to compare against yet (Turner's data
  would give us some). For comparison, the shotshaper model's validation
  against three measured throws came up 13–19 m short (Giljarhus 2022); its
  roll formula (next section) may be part of why.

## Known gaps, and what would close them

- **Damping coefficients are Frisbee numbers.** Roll damping `C_Rp` is the one
  that matters: for a Moraine at 24 m/s thrown flat, halving it gives
  79 m / 26 m of turn (from 73 m / 21 m), doubling it 62 m / 11 m. `C_Mq` and
  `C_Nr` move flights by a few metres at most. Adam Turner's 2025 Waterloo thesis identified
  coefficients from 3D-tracked golf-disc throws, wobble included; requested.
- **No wobble** (nutation) or off-axis torque at release. (Turner found that
  modelling wobble barely improved his trajectory predictions.)
- **One mass** (175 g) for every disc.
- **Wind** is in the maths (we subtract it) but static and zero for now.
- **Rolling moment from spin** (`C_Rr`) and the Robins–Magnus side force are
  left out (small; measured values disagree).
- **Ground play** is the physics engine with tuned friction, not aerodynamics.

## History: why not shotshaper

The game started on [shotshaper](https://github.com/kegiljarhus/shotshaper)
(Giljarhus et al. 2022): its CFD tables for four discs and its model. We left
it for two reasons:

1. **Roll rate.** shotshaper rolls the disc at `−M / (ω (I_xy − I_z))`
   (Giljarhus 2022, eq. 11): the body-axis Euler equation with the yaw rate
   set to the spin and the wobble dropped. For a flat disc `I_z ≈ 2 I_xy`, so
   that is about **twice** the steady precession rate that Hummel's full
   equations give, `M / (I_z r)` (as for any gyroscope; our 6-DOF reference
   integration agrees). Switching changed flights a lot: with the same tables,
   a flat 24 m/s distance drive went from 60 to 86 m.
2. **License.** Its tables are GPL-3.0. Ours are built from published
   measurements, so the game ships no GPL data.

Also from that era: constant spin and no damping terms (now Hummel's), and
the 5.2 rad/s per m/s spin rule (kept).

## References

- S. A. Hummel, *Frisbee Flight Simulation and Throw Biomechanics*, MS thesis,
  UC Davis, 2003. [PDF](https://morleyfielddgc.files.wordpress.com/2009/04/hummelthesis.pdf)
- N. M. Kamaruddin, *Dynamics and Performance of Flying Discs*, PhD thesis,
  University of Manchester, 2011.
  [PDF](https://pure.manchester.ac.uk/ws/portalfiles/portal/54511821/FULL_TEXT.PDF)
- N. M. Kamaruddin, J. R. Potts, W. J. Crowther, "Aerodynamic performance of
  flying discs", *Aircraft Engineering and Aerospace Technology* 90(2), 2018.
  [accepted version](https://shura.shu.ac.uk/14521/)
- J. R. Potts, W. J. Crowther, "Frisbee aerodynamics", AIAA 2002-3150; and
  W. J. Crowther, J. R. Potts, "Simulation of a spin-stabilised sports disc",
  *Sports Engineering* 10, 2007.
- K. E. T. Giljarhus, M. T. Gooding, J. Njærheim, "Disc golf trajectory
  modelling combining computational fluid dynamics and rigid body dynamics",
  *Sports Engineering* 25:26, 2022. [open access](https://link.springer.com/article/10.1007/s12283-022-00390-5)
- S. F. Hoerner, *Fluid-Dynamic Drag*, 1965 (flat-plate drag).
- A. Turner, *Dynamics of Golf Discs using Trajectory Experiments for
  Parameter Identification and Model Validation*, MASc thesis, University of
  Waterloo, 2025. [record](https://uwspace.uwaterloo.ca/items/fdcda51d-b752-4669-95e1-af5bf77da735)
  (restricted; copy requested).
