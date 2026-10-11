# Baskets and one playable hole

A design for the first piece of disc golf in discwalk: a basket that catches
discs the way a real one does, and a single hole you can play from a tee with a
stroke count.

The flight model is already honest — `disc_model.gd` is checked against
shotshaper's own numbers in `tools/flight_test.gd`. The point of this work is to
give those flights somewhere to land without undermining that honesty. A basket
that catches on a dice roll would make the simulation pointless.

## Scope

In:

- A basket in the world: pole, tray, top band, chains. Discs are caught, spat
  out, clanged off the band, or missed entirely.
- Auto-siting one hole per generated world, deterministic from the seed, plus a
  key to place the hole by hand.
- Stroke counting from tee to made putt, and a HUD readout.

Out, deliberately:

- Courses, multiple holes, par, scorecards. That's the README's "Disc golf
  mechanics" item and depends on this one.
- Penalties, out-of-bounds, mandos. See [Rules](#rules).
- Saving a hole to a file. That belongs with the README's world export item.

## The pieces

| File | Responsibility | Depends on |
|---|---|---|
| `scripts/basket.gd` | The physical target: geometry, colliders, and the chain/catch test | `terrain`, `voxel_mesh.gd` |
| `scripts/hole.gd` | The hole as a game object: tee, basket, strokes, state | `basket.gd`, `terrain` |
| `tools/basket_test.gd` | Headless PASS/FAIL for catching and siting | — |
| `tools/basket_shots.gd` | Screenshots | — |

Three existing files change, each as little as possible:

- **`scripts/disc.gd`** — roughly ten lines in `_integrate_forces`, next to the
  existing lake loop. It hands the tick's swept segment to the basket and takes
  back a velocity. No chain maths here.
- **`scripts/thrower.gd`** — counts a stroke per disc throw (not per cube
  throw), and forwards catches to the hole.
- **`scripts/main.gd`** — builds the hole after terrain generation, adds the
  readout, binds `B`.

The boundary that matters: **`disc.gd` never learns the rules of disc golf, and
`hole.gd` never learns physics.** Only the basket knows about chains; only the
hole knows about strokes. Delete `hole.gd` and you still have a basket to throw
at.

## The basket

PDGA-ish proportions, in metres, so the existing flight model stays meaningful:

| Part | Size |
|---|---|
| Top band | ring at **1.32 m**, 0.635 m across |
| Chain zone | cylinder, radius **0.30 m**, from y **0.75 m** to **1.30 m** |
| Tray rim | **0.66 m** high, 0.635 m across, 0.17 m deep |
| Pole | 0.05 m radius, ground to band |

Pole, tray and band are voxel-built through the `voxel_mesh.gd` helpers, so the
basket matches the oaks and clouds and scales with `block_size` the way trees
do. The chains are about twelve thin unlit bars in two rings — they read
correctly at distance and cost nothing.

### Colliders versus swept geometry

The same split the codebase already uses for trees, where trunks are colliders
and branches and leaves are marched through:

- **Pole and tray are real `StaticBody3D` colliders.** They are fat, static
  targets that Jolt handles well, and the tray has to physically hold a caught
  disc and let a missed putt clatter off its outside.
- **Chains and the top band are swept.** Both are thin enough that a 0.22 m
  disc at 25 m/s would tunnel straight through a collider.

### The chain model

The leaf model in `disc.gd:157` is `v *= pow(leaf_keep_per_metre, metres)`. That
is the wrong shape for chains, and the reason is worth recording: a pure ratio
is scale-invariant, so it takes the same *fraction* of speed at any speed. Tuned
to stop an 8 m/s putt over the ~0.3 m of chain, it equally stops a 25 m/s drive,
and every shot becomes a make. What makes real chains interesting is that they
have finite mass — a fast disc shoves them aside and keeps most of its energy.

So the chains absorb a **bounded impulse**. Per sample step:

```gdscript
var dv := minf(speed * (1.0 - pow(chain_drag_per_metre, metres)),
               chain_max_impulse / mass)
```

Starting values, all `@export` so they can be tuned in the editor:

| Knob | Value | Meaning |
|---|---|---|
| `chain_drag_per_metre` | 0.01 | fraction of speed kept per metre of chain |
| `chain_max_impulse` | 1.5 N·s | hard cap on momentum the chains can absorb |
| `chain_kick` | 0.08 | random sideways rattle, as a fraction of the speed absorbed |
| `chain_down_bias` | 0.35 | share of absorbed speed redirected downward, so a dying disc drops into the tray |
| `band_bounce` | 0.35 | speed kept along the hit axis off the top band |
| `catch_speed` | 2.5 m/s | at or under this, inside the cage, it's caught |
| `sweep_step` | 0.05 m | march resolution through the chain volume |

`chain_drag_per_metre` is deliberately brutal — keeping 1% per metre means the
ratio term alone would stop almost anything. **That is the point: the ratio is
not the discriminator, the impulse cap is.** Working it through for a typical
~0.3 m traversal of the chain volume, with `mass = 0.175` from `disc.gd:64`, so
the cap is 1.5 / 0.175 ≈ 8.6 m/s:

| Shot | Ratio term | Capped Δv | Exit speed | Result |
|---|---|---|---|---|
| 8 m/s putt | 6.0 m/s | 6.0 (uncapped) | 2.0 m/s | under `catch_speed` → caught |
| 25 m/s drive | 18.7 m/s | 8.6 (capped) | 16.4 m/s | flies on → spit-out |

Below the cap the chains swallow the disc; above it they can only take their
8.6 m/s and the rest carries through. That one clamp is the whole reason putting
feels different from driving, and it produces spit-outs out of the physics
rather than out of a random number.

Traversal length varies with approach angle — a centred putt crosses about
0.3 m, an edge clip much less, a dead-centre line up to the full 0.6 m — so the
spread that turns "caught" into "caught 90% of the time" comes from the geometry
and the rattle, not from a tuned probability.

These are starting values derived from the arithmetic above, not measured ones.
`tools/basket_test.gd` is the source of truth: tune against its pass rates and
update this table with what actually lands.

### Catch test

After the chain response, a disc is caught when it is inside the cage column
(radius ≤ 0.30 m), between the tray floor (0.49 m) and the band (1.32 m), and
slower than `catch_speed`. Caught means: park it in the tray, freeze it, beam
off, emit `caught(disc)`.

The catch test runs **whether or not the disc touched chains**, and the region
extends below the chain volume down to the tray floor. That is what makes a
lobbed disc dropping straight into the tray count as a make, and what catches a
disc the chains have already killed as it falls the last few centimetres.

Spit-outs, band clangs, pole deflections and discs sailing over the top all fall
out of the geometry with no special cases.

### Interface

`disc.gd` sees exactly one function, guarded by a `distance_squared_to` reject
so discs elsewhere in the world cost almost nothing:

```gdscript
# basket.gd
signal caught(disc)

## Resolve one physics tick's swept path p0 -> p1 against this basket.
## Returns {v: Vector3, caught: bool, hit: String}
## where hit is "", "chains", "band" or "cage".
func sweep(p0: Vector3, p1: Vector3, v: Vector3) -> Dictionary
```

### Two interactions to handle up front

- **Collect (`C`)** must pull a holed disc back out. `start_collect` clears
  `resting`, so the capture freeze needs releasing there too.
- A caught disc must **not** emit an ordinary `came_to_rest`, or `hole.gd` would
  count it as a normal lie instead of a make.

## The hole

### Siting

The tee is the player spawn — world centre, already cleared by
`spawn_clear_radius = 20` — so you always start on the tee.

The basket is sited from the seed with its own RNG stream, following the
convention at `flora.gd:69`. Sample candidate columns in a **60–120 m** annulus
around the tee and reject any that are:

- underwater, or on shore sand (`terrain.is_underwater`, `terrain.is_shore`)
- on a steep slope (more than one block of fall across the 4-neighbourhood)
- inside the moraine belt at the world edge (`moraine_width`, plus a margin)
- within 2 m of a trunk column

Score the survivors — prefer mid-range distance and a few oaks between tee and
basket, since a dead-open shot is dull — and take the best. If nothing passes,
relax the constraints and retry rather than fail: a world with no hole is worse
than a world with a mediocre one.

Siting is deterministic from `world_seed`, so the same seed always gives the
same hole. `N` (new world) re-sites.

### Rules

Minimal, on purpose:

- Every **disc** throw while the hole is unfinished counts one stroke.
- **Cube** throws (right click) count for nothing. They're a physics toy.
- No penalties and no out-of-bounds. A disc in a lake is just a bad lie.
- Holing out completes the hole. Later throws don't count until the hole resets.

The intended loop is already in the game: throw, `G` (goto) to your disc, throw
again. The README calls warp "the first piece" of disc golf mechanics, and it is.

**Known looseness:** nothing stops you walking up to the basket and dropping a
disc in for a 1. Enforcing "first throw from the tee" is real rule surface and
minimal rules were chosen deliberately, so it stays out of this version. This is
a recorded decision, not an oversight.

### Controls and display

`B` sets the hole where you're looking: tee at your feet, basket at the ground
point under the crosshair, strokes reset. One key does both the manual override
and the reset. `B` is free — the README notes it was retired when rest beams
moved onto `P`.

The basket gets the same tall faint beacon that resting discs get at
`disc.gd:300`, on the same `P` toggle, because a 0.635 m target at 90 m through
oak trunks is otherwise invisible.

A small warm label top-left reads `Hole · 86 m · stroke 3`, distance live so you
can pick a disc. A make prints `Holed in 4` through `thrower._note()`, the
transient top-centre line that already shows "warped 42 m".

While in there, rename `warp_label` to `note_label` in `thrower.gd` and
`main.gd`. It stops being about warping once it reports makes, and the rename is
a handful of lines.

### Flag

`--no-hole` suppresses the basket, so the existing screenshot tools can keep it
out of frame. Documented in `docs/CONFIG.md` alongside the other flags.

## Testing

`tools/basket_test.gd`, headless PASS/FAIL in the style of the other eight
scripts in `tools/`:

| Case | Expectation |
|---|---|
| 5 m putt at putting speed, ×40 | caught ≥ 90% |
| 10 m approach, ×40 | caught in the majority |
| 25 m/s flat drive into the chains, ×20 | punches through in the majority |
| Thrown into the pole | deflects, never caught |
| Passing above 1.32 m | untouched, clean miss |
| Siting across 20 seeds | every basket legal and 60–120 m out |
| Hole out in 3 throws | reports `strokes == 3` |
| `C` on a holed disc | pulls it out of the tray |

`tools/basket_shots.gd` renders the basket close up, from the tee, mid-putt, and
with a disc resting in the tray.

Because `disc.gd` changes, these must stay green: `throw_test`, `landing_test`,
`toggles_test`, `hud_test`, `smoke_test`, and above all **`flight_test`**, which
validates carry and drift against shotshaper within 10% and 4 m. Any drift there
means the basket work has damaged the flight model.

## Docs to update

- `README.md` — tick the baskets roadmap item, add `B` to the controls table
- `docs/ARCHITECTURE.md` — add `basket.gd` and `hole.gd` to the file tour and
  the runtime scene tree
- `docs/CONFIG.md` — `--no-hole`, and a basket knobs section
