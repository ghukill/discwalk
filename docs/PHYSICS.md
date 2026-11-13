# The physics of discwalk, and why

This is the rationale for the flight model: what is simulated, which equations
and numbers we use, where each comes from, and what we assumed. The approach is
deliberately **cherry-picked**: the best available equations (Hummel 2003) plus
the best available measurements of real golf discs (Kamaruddin 2011), joined by
a few simple, stated physical assumptions where no data exists.

Code: `scripts/disc_model.gd` (the maths), `scripts/flying_disc.gd` (the body in
the world), `scripts/wind.gd` (the air), `tools/discs/` (how the disc tables are
made and checked), `tools/flight_table.gd` (prints every flight number quoted
in the docs, from the model).

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
| Roll and pitch damping `C_lp`, `C_mq` | −`C_Lα`/8 ≈ −0.3, per `p·d/2V` | strip theory on each disc's measured lift slope; see [Damping](#damping) | fair, and it barely matters: ×4 moves a drive 3 m |
| Spin down `C_nr` | −0.0034, per `r·d/2V` | Hummel 2003's long-flight fit, made non-dimensional at his flight speed; a skin-friction estimate agrees | fair; small effect |
| Roll moment from spin `C_Rr` | 0 (left out) | Hummel's flight fit and Potts & Crowther's wind tunnel disagree even in sign, and both are for a Frisbee; see [Known gaps](#known-gaps-and-what-would-close-them) | open |
| Wind | log profile, roughness 0.05 m, sum-of-sines gusts | standard surface-layer model; see [Wind](#wind) | good for the mean; gusts are for feel |
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
- **Moments** (Hummel eq. 2.8), with axes x̂ = airflow projected on the
  disc plane (roll), ŷ = x̂ × **n** (pitch, to the right), and rates p, q about
  them, `qAd = ½ρv²·A·d`, and `k = d / 2v` making each rate non-dimensional
  (see [Damping](#damping)):
  - roll `R = C_lp·(p·k)·qAd`
  - pitch `M = (C_M(α) + C_mq·(q·k))·qAd`
  - spin down `N = C_nr·(r·k)·qAd`
- **Gyroscope.** A spinning disc doesn't simply pitch up under `M`: its
  angular momentum `H = I_z r n` precesses. Hummel integrates the full Euler
  equations, `I_xy dω/dt + I_z r (ω × n) = M_⊥`. The `I_xy dω/dt` term is
  wobble (nutation), which spins at about `2r` (~200 rad/s) and which the
  damping kills in a fraction of a second. We drop it and keep the **steady precession**
  `M_⊥ = I_z r (ω × n)`: two linear equations for p and q, solved exactly
  every tick (`DiscModel._attitude()`). Without damping, the roll rate is
  `p = M / (I_z r)`: the textbook gyroscope. That slow roll is **turn**
  (early, fast, nose-down moment) and **fade** (late, slow, nose-up moment).
- **Spin down:** `I_z dr/dt = N`, an exponential decay at
  `C_nr·k·qAd / I_z`: ~3 %/s at 24 m/s, ~1.2 %/s at 10 m/s. A long drive
  loses ~10 % of its spin; slower spin means a bit more fade at the end.
- **Wind** is not a force. All of the above works on the disc's velocity
  *through the air*, so the wind at the disc's height is subtracted from its
  velocity first, and that is the whole of it ([Wind](#wind)).
- **Landing:** on first contact with anything the aerodynamics switch off for
  good and the physics engine takes over (skips, rolls, flops). A
  simplification: a skipping disc really is still flying a little.

**Is the shortcut OK?** `tools/discs/hummel_reference.py` integrates the
*full* equations (wobble and all, 256 substeps per tick) for the same throws;
the game lands within ~1–3 % (checked every run of `tools/flight_test.gd`).

## Damping

The three rate terms are where this model departs from Hummel's numbers, and
the reasoning is worth having in one place.

**What they are.** A disc that is rolling at rate `p` has one side moving down
through the air and the other up, which changes the local angle of attack by
`p·y / V` at a distance `y` from the axis. That makes a moment opposing the
roll. The same goes for pitch, and skin friction does it for spin. Because the
cause is a *change of airflow angle*, the moment coefficient depends on the
non-dimensional rate `p·d / 2V`, not on `p` itself. Every flight-dynamics text
writes rate derivatives this way; the moment then grows with `V`, not `V²`.

**What Hummel published.** Coefficients per rad/s: `C_Mq = −0.0144`,
`C_Rp = −0.0125`, `C_Nr = −3.41e-5`, fitted to one flight (f2302) of a 27 cm
Frisbee released at 13.5 m/s. At that one speed the two forms are the same
thing. We used to apply his numbers unchanged to 21 cm golf discs at 24–36 m/s,
where they are too big by `(V / 13.5) × (0.269 / 0.211)`: 2.3× at 24 m/s and
3.4× at 36 m/s. Two more things say they were never meant to steer a flight:

- Hummel's own check (thesis §3.5): swapping his short-flight values for his
  long-flight ones, 2–3× apart, gave trajectories that were "nearly identical
  except for the damping of the [roll and pitch] oscillations". For him these terms damp
  wobble. For us they were moving a drive 10–20 m and holding discs in a turn
  they should have faded out of (the nose followed the roll down at a fifth of
  the roll rate; at full power, a third).
- Wobble. With his numbers a golf disc's flutter dies in ~0.02 s at 24 m/s,
  less than half a turn. Real off-axis wobble is visible for many turns, a
  good fraction of a second.

**What we use.** Strip theory for a round wing: integrate the lift change
`C_Lα · (p·y / V)` over the disc and the roll damping is
`C_lp = −C_Lα / 8` per `p·d / 2V`; pitch is the same integral the other way.
`C_Lα` is each disc's measured lift slope (Kamaruddin Table 5.6), so
`C_lp = C_mq` = −0.27 (Erratic) to −0.32 (Outwash), written into the disc JSON by
`build_tables.py`. Non-dimensionalised the same way, Hummel's Frisbee values
are −0.5 (short flights) to −1.4 (long): the same order, and a deep-rimmed
Frisbee should have more. Wobble now takes ~0.2 s to die at 24 m/s.

Spin down keeps Hummel's long-flight number, made non-dimensional at his
flight speed: `−3.41e-5 × 2 × 13.5 / 0.269 = −0.0034`. Turbulent skin friction
(`C_f ≈ 0.005`) on the two faces of a spinning disc in a cross flow comes to
about the same. (His code applies `C_Nr·r` with no dynamic pressure at all,
his eq. 2.8c with it; we had the equation's form at a golf disc's speed, which
bled spin 2–3× too fast.)

**How much it matters now.** Almost not at all, which is the right place for
the least-measured numbers in the model to be. Moraine, 24 m/s, flat
(`tools/flight_table.gd`): no damping 84 m, ours 83 m, ×2 82 m, ×4 80 m; spin
down ×0 to ×3 moves it under a metre.

## The discs

Seven discs, each built from the wind-tunnel data of one real disc. Names are
Michigan glacial landforms. (Player's guide, with flights to try:
[DISCS.md](DISCS.md).) Drivers are listed from understable to overstable.

| Disc | Kind | Data from | Character (in game) | `C_M` at 0° | aero centre |
|---|---|---|---|---|---|
| **Kettle** | putter | Innova Aviar | short and straight at putting speed (16 m/s: 37 m) | −0.018 | 5 % |
| **Drumlin** | midrange | Innova Roc | steady, fades with a little hyzer | −0.014 | 7 % |
| **Esker** | midrange | Discraft Buzz | straight-to-understable; likes some hyzer | −0.034 | 10 % |
| **Till** | distance driver | Discwing Quarter K | very understable: turns over flat, needs 20–30° hyzer (hyzer flip) | −0.038 | 13 % |
| **Outwash** | distance driver | "Storm" (maker not given) | slightly understable; long with 10–15° hyzer (~85 m at 23 m/s) | −0.026 | 9 % |
| **Moraine** | distance driver | Innova Wraith | the distance driver: 10° hyzer at 24 m/s flips up and goes ~87 m (20° and a touch of nose down: 94 m) | −0.020 | 15 % |
| **Erratic** | distance driver | Discraft Flick | very overstable: fades left even thrown anhyzer | −0.007 | 21 % |

The throw HUD shows each disc's kind and a one-word stability (straight,
stable, understable, overstable, "very ...") in small print above its name.
"Distance driver" follows the rim: these four have 2.1–2.3 cm rims
(Table 4.1; the Storm's isn't given).

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
- **Wind:** head, tail and cross winds each do what they should, and the aim
  arc lands where the disc does in all of them (`tools/wind_test.gd`).
- **Character:** the checks in `tools/flight_test.gd` (Erratic fades from
  anhyzer, Till turns over flat, Moraine hyzer-flips long, Kettle is short and
  straight, forehand mirrors backhand, more hyzer bends more, spin bleeds off).
- **Real-world sanity:** distance per speed. A Moraine at 20 m/s (45 mph)
  carries ~65 m flat, at 24 m/s (54 mph) ~87–94 m with some hyzer, at 65 mph
  ~125 m and at 80 mph ~160 m (on 40° of hyzer), before ground play. That is
  in the range players quote for those arm speeds, but we
  have no measured throws of our own to compare against yet (Turner's data
  would give us some). For comparison, the shotshaper model's validation
  against three measured throws came up 13–19 m short (Giljarhus 2022); its
  roll formula (next section) may be part of why.

## Known gaps, and what would close them

- **Damping is theory, not measurement** ([Damping](#damping)). It barely
  moves a flight, but nobody has measured it on a golf disc. Adam Turner's
  2025 Waterloo thesis identified coefficients from 3D-tracked golf-disc
  throws, wobble included; requested.
- **Everything is flippy at full power.** Lift goes as speed squared, so at
  80 mph a disc carries its weight at about −3° angle of attack, where every
  measured `C_M` is strongly nose-down: flat releases turn over within a
  second, and only the Erratic stays on its feet. That is what the tables
  say, and big arms do reach for overstable plastic and a lot of hyzer. But
  there is a gap in the bag between the Moraine and the Erratic, where a
  touring pro's driver would sit (`build_tables.py` can make one: `cm_shift`).
- **No wobble** (nutation) or off-axis torque at release. (Turner found that
  modelling wobble barely improved his trajectory predictions.)
- **One mass** (175 g) for every disc.
- **Wind** has no shelter: trees and hills do not block it, and there are no
  updrafts over a rise.
- **Rolling moment from spin** (`C_Rr`): a spinning disc's advancing side
  makes a little more lift, and that moment precesses as a slow *pitch*.
  Kamaruddin's discs did not spin, so his data cannot show it. Hummel's
  flight fit says nose-up; Potts & Crowther's Frisbee table (in Hummel's
  Appendix B) has the other sign and a third of the size. At the Frisbee
  size it would pitch a drive up several degrees a second, which golf discs
  visibly do not do, so it is left at zero. If it is real but small it would
  make every disc a little more stable at speed; of everything missing, this
  is the one most likely to matter. The Robins–Magnus side force is left out
  too (small).
- **Ground play** is the physics engine with tuned friction, not aerodynamics.

## Wind

`scripts/wind.gd`. Off (calm) until you ask for it: **F** steps the strength,
**Z** turns it (or `--wind=10@270`).

**The model.** One body of air over the whole course, with three parts:

- **Mean.** A speed and the compass bearing it blows *from*, as a forecast
  gives it. The speed is the one you would feel: true at head height (2 m).
- **Profile.** The ground slows the wind. We use the surface-layer log law,
  `U(h) = U(2 m) · ln(h / z₀) / ln(2 m / z₀)`, with roughness `z₀ = 0.05 m`
  (rough grass, scattered trees), `h` above the ground under the disc. That
  is ×0.62 at half a metre, ×0.81 at 1 m, ×1.25 at 5 m, ×1.44 at 10 m,
  ×1.62 at 20 m. It is why a low line "stays under the wind" and a sky-high
  one gets carried away.
- **Gusts.** The speed breathes by ±20 % and the direction swings ±10°, as a
  few slow sines (2–17 s periods), the same everywhere at once. Deterministic,
  not random: the same clock gives the same gust. `--gusts=0` holds it steady.

**What it does to a disc.** Nothing special. The flight model takes the
velocity through the air, so the wind at the disc's height is subtracted and
the same tables do the rest. What comes out is what golfers already know
(Moraine, 54 mph, 10° up, 10° hyzer, RH backhand; steady 10 mph;
`tools/flight_table.gd`, checked by `tools/wind_test.gd`):

| | Carry | Ends | Peak | Why |
|---|---|---|---|---|
| Calm | 87 m | 5 m left | 7.7 m | |
| Headwind | 58 m | 21 m right | 8.8 m | More airspeed: more lift (it climbs) and more turn (it flips), and more drag all the way. "A headwind makes a disc less stable." |
| Tailwind | 78 m | 13 m left | 4.5 m | Less airspeed: less lift (it is pushed down) and it fades as if thrown soft. |
| Left to right | 97 m | 22 m right | 6.5 m | Carried downwind. On a hyzer the wind is on top of the disc, pressing it down. |
| Right to left | 87 m | 18 m left | 9.0 m | Carried downwind, and the wind gets under the hyzer and lifts it. |

A putt shows it too: a 15 mph headwind lifts a 20 mph putt to 3 m and hangs
it for 3.5 s; the same tailwind drops it at 6 m instead of 10.

**The aim arc and the putt assist** simulate the wind as it is blowing at
that instant, held still for the whole flight (`flight_sim.gd`). In a steady
wind the arc is exact; in a gusty one it breathes, and the throw meets
whatever gust arrives.

**Seeing it.** A pale arrow on the heading dial (the way the air is going,
against your heading) with the speed and "head / tail / L→R / R→L" under it;
streaks drifting through the air round you at the wind's own speed for their
height; the clouds; the flowers (`wind_fx.gd`).

**Not modelled:** shelter behind trees and hills, updrafts, turbulence smaller
than a gust, and wind on a disc once it has landed.

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

Also from that era: constant spin and no damping terms (now Hummel's form,
[non-dimensional](#damping)), and the 5.2 rad/s per m/s spin rule (kept).

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
