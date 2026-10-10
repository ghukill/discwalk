# Configuration

discwalk has a small set of knobs. All distances are in **metres** unless noted.

## How to set things

There are three ways, from quickest to most permanent:

1. **Command line** (after a bare `--`, which separates Godot's own flags from ours):

   ```sh
   # macOS
   /Applications/Godot.app/Contents/MacOS/Godot --path . -- --block-size=0.5
   # or via `open`
   open -n ~/Applications/Godot.app --args --path ~/projects/discwalk -- --block-size=0.5
   # Linux (T480)
   ../tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . -- --block-size=0.5
   ```

2. **Godot editor**: open `scenes/main.tscn`, select the `Terrain` (or `Terrain/Flora`) node, and change values in the Inspector. Those values are saved into the scene.

3. **Code defaults**: the `@export var ...` lines at the top of `scripts/terrain.gd` and `scripts/flora.gd`.

Command-line flags override the scene and the code defaults.

## Command-line flags

| Flag | Default | What it does |
|---|---|---|
| `--block-size=<m>` | `1.0` | Edge length of one voxel. `0.5` = twice as fine. Valid range: 0.125 to 4. |
| `--debug-keys` | off | Prints every key press/release to stdout. Useful for diagnosing remote input (VNC). |

The dev tools accept the same flags, e.g.

```sh
$G --headless --path . --script res://tools/smoke_test.gd -- --block-size=0.5
$G --path . --script res://tools/screenshot.gd -- /tmp/shots --block-size=0.5
```

## Block size

`block_size` only changes **how finely** the world is chopped into blocks. It does not change the world itself. Hills, lakes, tree positions and flower patches all come from the seed in metres, so the same seed gives the same landscape at any block size, just chunkier or finer.

Measured on seed 1848 (greedy meshing, branching oaks):

| | 1.0 (default) | 0.5 | 0.25 |
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
| `block_size` | 1.0 | See above. |
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
| `speed_per_level` | `thrower.gd` | 4.0 | m/s per power level (power 10 = 40 m/s). |
| `max_discs` | `thrower.gd` | 12 | Older discs get cleared away (blocks and flying discs together). |
| `VISUAL_SPIN_MAX` | `flying_disc.gd` | 14 rad/s | How fast the disc *looks* like it spins (real spin would strobe). |
| `LANDED_SPIN_MAX` | `flying_disc.gd` | 25 rad/s | Real spin handed to the physics on landing (roll-on-edge flavour). |
| `back`, `up`, `lead` | `follow_cam.gd` | 1.8, 0.5, 4.0 m | Follow cam: distance behind, height above, look-ahead. |
| `follow_rate`, `aim_rate` | `follow_cam.gd` | 14, 8 /s | Follow cam smoothing (higher = snappier). |
| panel sliders | `throw_panel.gd` `ROWS` | | Ranges and defaults for speed, launch angle, nose, hyzer, spin. |
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
