# Configuration

discwalk has a small set of knobs. All distances are in **metres** unless noted.

## How to set things

There are three ways, from quickest to most permanent:

1. **Command line** (after a bare `--`, which separates Godot's own flags from ours):

   ```sh
   # macOS
   /Applications/Godot.app/Contents/MacOS/Godot --path . -- --block-size=1
   # or via `open`
   open -n ~/Applications/Godot.app --args --path ~/projects/discwalk -- --block-size=1
   # Linux (T480)
   ../tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . -- --block-size=1
   ```

2. **Godot editor**: open `scenes/main.tscn`, select the `Terrain` (or `Terrain/Flora`) node, and change values in the Inspector. Those values are saved into the scene.

3. **Code defaults**: the `@export var ...` lines at the top of `scripts/terrain.gd` and `scripts/flora.gd`.

Command-line flags override the scene and the code defaults.

## Command-line flags

| Flag | Default | What it does |
|---|---|---|
| `--block-size=<m>` | `0.25` | Edge length of one voxel. Bigger = chunkier but faster to build and lighter on memory (`0.5`, `1`). Valid range: 0.125 to 4. |
| `--debug-keys` | off | Prints every key press/release to stdout. Useful for diagnosing remote input (VNC). |
| `--ui-scale=<x>` | `1.0` | Extra size for the HUD and help text (0.6–3). `-` / `=` change it in game. |
| `--no-clouds` | off | Start with clouds hidden (K shows them). |
| `--no-hole` | off | Leave the world without a basket or a hole (the screenshot tools use this). |

The dev tools accept the same flags, e.g.

```sh
$G --headless --path . --script res://tools/smoke_test.gd -- --block-size=1
$G --path . --script res://tools/screenshot.gd -- /tmp/shots --block-size=1
```

## Block size

`block_size` only changes **how finely** the world is chopped into blocks. It does not change the world itself. Hills, lakes, tree positions and flower patches all come from the seed in metres, so the same seed gives the same landscape at any block size, just chunkier or finer.

Measured on seed 1848 (greedy meshing, branching oaks):

| | 1.0 | 0.5 | 0.25 (default) |
|---|---|---|---|
| Grid | 256² columns | 512² | 1024² |
| Terrain triangles | 50k | 190k | 737k |
| Tree voxels / triangles | 77k / 181k | 496k / 683k | 3.6M / 2.3M |
| World build (T480) | ~5 s | ~13 s | ~56 s |
| Memory (T480, headless) | ~190 MB | ~440 MB | ~1.7 GB |
| Walls (2 blocks) | 2 m | 1 m | 0.5 m |

Notes:

- **Walking feel**: collision is a smooth heightmap through the block centres, scaled uniformly, so a one-block step is always a 45° ramp (walkable). That means "a wall" is 2 blocks, which is 2 m at size 1.0 but 1 m at size 0.5.
- **Oaks** are measured in metres (trunk height, crown radius, 2 m trunks for big oaks), so they keep their size and gain detail. At 0.5 the limbs taper towards the tips.
- **Flowers** are already smaller than a block and their density is per square metre, so the meadow looks about the same at any block size.
- **Water level** sits 0.35 blocks below the lowest rim block, so lakes come out a little different at different sizes.
- Small sizes cost mostly **build time and memory**, not frame rate. Growing and meshing millions of tree voxels in GDScript takes a while at 0.25 (Macs are roughly 1.5× faster than the T480). Below 0.25 is untested.

## Terrain knobs (`scripts/terrain.gd`)

| Setting | Default | Meaning |
|---|---|---|
| `world_seed` | 1848 | Starting seed. Press **N** in-game for a random new one. |
| `block_size` | 0.25 | See above. |
| `world_size` | 256 | World edge length (m). Rounded to whole chunks. |
| `chunk_metres` | 32 | Chunk edge (m). One terrain mesh + one tree mesh per chunk, so the chunk count (64) stays the same at every block size. |
| `base_height` | 14 | Average ground height (m). |
| `hill_height` | 9 | Amplitude of the rolling hills (m). |
| `lake_count` | 7 | Kettle lakes to try to place. |
| `lake_radius_min` / `_max` | 7 / 15 | Kettle radius range (m). |
| `lake_depth` | 6 | How deep the kettle bowls are pressed (m). |
| `spawn_clear_radius` | 20 | Keep lakes this far from spawn (m). |
| `moraine_width` / `_height` | 14 / 12 | The ridge around the world's edge (m). |

## Throwing knobs

| Setting | Where | Default | Meaning |
|---|---|---|---|
| `speed_per_level` | `thrower.gd` | 4.0 | Tests only now: m/s per level in `throw(level)`. Cubes use the HUD speed. |
| `max_discs` | `thrower.gd` | 12 | Older discs get cleared away (blocks and flying discs together). |
| `VISUAL_SPIN_MAX` | `flying_disc.gd` | 14 rad/s | How fast the disc *looks* like it spins (real spin would strobe). |
| `landed_friction` | `flying_disc.gd` | 0.3 | Grip after landing. Lower = more skip and skid. Flat-grass ground play averages ~8 m at 0.7, ~16 m at 0.3, ~26 m at 0.15 (`tools/skip_test.gd`). |
| `landed_bounce` | `flying_disc.gd` | 0.35 | Bounce after landing (barely matters: discs land flat). |
| `LANDED_SPIN_MAX` | `flying_disc.gd` | 25 rad/s | Real spin handed to the physics on landing (roll-on-edge flavour). |
| `back`, `up`, `lead` | `follow_cam.gd` | 1.8, 0.5, 4.0 m | Follow cam: distance behind, height above, look-ahead. |
| `follow_rate`, `aim_rate` | `follow_cam.gd` | 14, 8 /s | Follow cam smoothing (higher = snappier). |
| `AIR_SIZE`, `GROUND_SIZE` | `paths.gd` | 0.08, 0.05 m | Path cube sizes. |
| `AIR_SPACING`, `GROUND_SPACING` | `paths.gd` | 0.5, 0.25 m | A path cube every this many metres. |
| `GROUND_DIM` | `paths.gd` | 0.5 | How much darker ground cubes are. |
| `ALPHA` | `paths.gd` | 0.55 | Path cube opacity (1 = solid). |
| `START_GAP`, `FADE_IN` | `paths.gd` | 0.875, 2.0 m | No cubes this close to the release; then a fade-in over this distance. |
| `NEAR_FADE_MIN`, `NEAR_FADE_MAX` | `paths.gd` | 1.0, 4.0 m | Cubes closer to the camera than MIN are invisible, fully there from MAX. |
| `FALL_GRAVITY`, `POOF_TIME`, `POOF_SWELL` | `paths.gd` | 3.5 m/s², 0.35 s, 1.8× | The P fall-and-poof. |
| `launch_min`, `launch_max` | `thrower.gd` | −45°, 85° | Launch angle limits (= view pitch). |
| `radius`, `PITCH_PX_PER_R` | `dials.gd` | 30 px (set by the HUD), 0.045 | Dial size; horizon scale (px per degree per px of radius). |
| `W`, `H`, `DISC_R`, `BAR_H` | `throw_hud.gd` | 300, 244, 46, 80 px | HUD block size, disc instrument radius, bar height (before scaling). |
| `CAM_ELEV`, `NOSE_GAIN` | `throw_hud.gd` | 20°, 1.8 | How far above we see the HUD disc from; how much nose is exaggerated. |
| `UI_REF_HEIGHT` | `main.gd` | 900 px | Window height where the overlay is 1×; taller windows scale it up. |
| `--ui-scale=<x>` | command line | 1.0 | Extra HUD scale on top (0.6–3); `-` / `=` change it in game. |
| `count`, `height_max` | `clouds.gd` | 11, 110 m | How many clouds; the highest one's altitude. |
| `low_count`, `low_above_trees`, `low_scale` | `clouds.gd` | 3, 18–30 m, 0.6 | The low, close puffs: how many, how far over the tallest treetop, how big. |
| `drift` | `clouds.gd` | (1.1, 0.35) m/s | Cloud drift (x, z); wind will drive this later. |
| `--no-clouds` | command line | | Start with clouds hidden (K shows them). |
| `RANGES`, defaults | `throw_setup.gd` | | Min/max/step for speed, nose, hyzer, spin; starting disc (dd2), 24 m/s, flat, spin locked. |
| `REPEAT_DELAY`, `REPEAT_RATE`, `REPEAT_RAMP`, `REPEAT_MAX` | `throw_setup.gd` | 0.3 s, 10, 30, 45 /s | Arrow hold-to-repeat: delay, then steps/s ramping up to the max. |
| disc tables | `data/discs/*/*.json` | | One file per disc; see `data/discs/README.md`. |
| `leaf_keep_per_metre` | `disc.gd` | 0.72 | Fraction of speed kept per metre of leaves. |
| `bark_bounce` | `disc.gd` | 0.4 | Speed kept along the hit axis when bouncing off bark. |
| `SIZE` | `disc.gd` | 0.22 | Disc block edge (m). |
| `collect_speed0` | `disc.gd` | 1.0 | Collect: starting roll speed (m/s), about ¼ walking pace. |
| `collect_ramp` | `disc.gd` | (0.6, 0.35) | Collect: speed target grows by a·t + b·t². |
| `collect_max_speed` | `disc.gd` | 25 | Collect: top speed (m/s). |
| `collect_accel` | `disc.gd` | 14 | Collect: max push (m/s²). Lower = more easily stuck behind ledges. |
| `collect_timeout` | `disc.gd` | 40 | Collect: seconds before a stuck disc gives up. |
| bounce / friction | `disc.gd` `_ready()` | 0.35 / 0.7 | Against ground and trunks. |

## Flora knobs (`scripts/flora.gd`)

| Setting | Default | Meaning |
|---|---|---|
| `grove_spacing` | 6 | Spacing of candidate tree spots (m). Lower = denser groves. |
| `region_size` | 64 | Flowers are batched into regions this big (m) for culling. |
| `flower_view_distance` | 110 | Flowers fade out beyond this distance (m). |

Wind sway lives in `shaders/sway.gdshader` (`sway_strength`, `sway_speed`, `wind_dir`).

## Basket knobs (`scripts/basket.gd`)

The chains are not physics bodies (too thin: a fast disc would tunnel through).
Each tick the disc's swept path is marched through the chain volume, the same
trick `flora.gd` uses for leaves. The chains push back with a **limited force**,
so how much a disc loses depends on how long it spends in the curtain. A putt
dawdles through over several ticks and is wrung out; a drive is past in one and
keeps nearly everything. `chain_max_force` is the knob that sets that line.

| Setting | Default | Meaning |
|---|---|---|
| `chain_max_force` | 28 | Hardest the chains push back (N). **The main feel knob.** Higher = more putts stick and drives start getting caught; lower = more spit-outs. |
| `chain_drag_per_metre` | 0.01 | Fraction of speed kept per metre of curtain. Deliberately brutal; the force limit above is what discriminates. |
| `chain_kick` | 0.08 | Random sideways rattle, as a fraction of the speed absorbed. |
| `chain_down_bias` | 0.35 | Share of absorbed speed sent downward, so a dying disc drops into the tray. |
| `band_bounce` | 0.35 | Speed kept along the hit axis when the top band is clipped. |
| `catch_speed` | 2.5 | Horizontal speed (m/s) at or under which the cage keeps the disc. Measured horizontally because the tray arrests a falling disc by itself. |
| `sweep_step` | 0.05 | March resolution through the chain volume (m). |

Geometry is PDGA-ish and fixed in metres, independent of `block_size`: 1.32 m to
the top band, a 0.635 m tray, chains between 0.75 m and 1.30 m. The basket is
built from smooth primitives rather than voxels, because at a 0.25 m block size
the tray would be two and a half blocks across.

`tools/putt_probe.gd` sweeps putt distance, speed and loft and reports what goes
in — run it after changing any of the above:

```sh
$G --headless --path . --script res://tools/putt_probe.gd -- --block-size=1
```
