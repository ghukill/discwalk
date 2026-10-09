# Architecture

A short tour of how discwalk is put together. It is written for "future us" opening the project after a break.

## Files

```
project.godot            Godot project settings (window, physics tick, MSAA)
scenes/main.tscn         The one scene: sky/environment, sun, Terrain, Player, HUD
scripts/main.gd          Glue: spawns the player, HUD text, N = new world, --debug-keys
scripts/terrain.gd       Height field, kettle lakes, chunk meshes, water, collision
scripts/flora.gd         Oaks (voxel trees) and wildflowers (MultiMesh)
scripts/player.gd        First-person walker: input bindings, movement, head bob
shaders/sway.gdshader    Wind sway for flowers (and grass, later)
tools/smoke_test.gd      Headless PASS/FAIL check
tools/screenshot.gd      Renders PNG views (needs a display/GPU)
docs/                    These docs + screenshots
```

Everything is plain GDScript on stock Godot 4.7, with no plugins or native code, so it runs unchanged on macOS, Linux and Windows.

## Scene tree at runtime

```
Main (main.gd)
├─ WorldEnvironment, Sun
├─ Terrain (terrain.gd)          rebuilt from scratch by generate()
│  ├─ Chunks/Chunk_x_z           one MeshInstance3D per chunk (scaled by block_size)
│  ├─ Lakes/Lake_i               flat transparent discs
│  ├─ Ground (StaticBody3D)      HeightMapShape3D + 4 invisible boundary walls
│  └─ Flora (flora.gd)
│     ├─ Trees/Trees_x_z         one MeshInstance3D of tree voxels per chunk
│     ├─ Trunks (StaticBody3D)   one box collider per trunk
│     └─ Flowers/<species>_x_z   MultiMeshInstance3D per species per 64 m region
├─ Player (player.gd)            CharacterBody3D + capsule + Head/Camera3D
└─ HUD/Help                      Label
```

## Units: metres vs blocks

This is the one idea worth keeping in your head.

- **Metres** are the world's real units. All settings, lake centres/radii, water levels, `height_at()`, `spawn_point()`, physics and the player are in metres.
- **Blocks** are grid units. `terrain.heights[iz * size + ix]` is the top of column `(ix, iz)`, counted in blocks. Tree voxel keys (`Vector3i`) are in blocks too.
- `block_size` (m per block) converts between them. Meshes are **built in block units** and the MeshInstance / CollisionShape nodes are **scaled by `block_size`**. That keeps the meshers simple (integer grid) and makes the size change a one-line scale.

Helpers on `terrain.gd`:

| Function | In | Out |
|---|---|---|
| `height_at(x, z)` | metres | metres |
| `col_of(m)` | metres | column index (clamped) |
| `col_height(ix, iz)` | columns | blocks |
| `is_shore(ix, iz)`, `is_underwater(ix, iz)` | columns | bool |
| `lake_edge_distance(x, z)` | metres | metres (negative = in a lake) |
| `spawn_point()` | | metres |

Noise is always sampled at **metre** coordinates, which is why the same seed looks the same at any block size.

## World generation pipeline (`terrain.generate()`)

1. **Base heights** (metres, float): FBM simplex "hills" + slow "swells" (drumlin-like) + a moraine ridge that rises within `moraine_width` of the edge.
2. **Kettles**: up to `lake_count` round bowls, kept off the moraine, away from spawn and from each other. Each one subtracts a smooth bowl from the height field.
3. **Quantise**: metres → whole blocks (`heights`).
4. **Fill lakes**: water level = lowest rim block (sampled on a ring at 92% of the radius) − 0.35 block. Columns at or below waterline + 1 block become shore (sand above water, mud below).
5. **Chunk meshes**: for each column, emit a top quad and side quads down to each lower neighbour. Hidden faces are never emitted. Colours come from layer depth (turf, dirt, stone, sand) plus a per-block hash jitter.
6. **Water**: one thin transparent cylinder per lake.
7. **Collision**: a `HeightMapShape3D` with one sample per column at block centres, plus 4 invisible boundary walls. Smooth collision means one-block steps behave like 45° ramps (the player allows 50°), and two-block steps are walls.
8. **Flora**: `flora.build(terrain)`, described next.

## Flora (`flora.gd`)

**Tree placement**
- Candidate spots on a jittered `grove_spacing` grid (metres).
- Grove noise picks the zone: grove (dense, big/medium), grove edge (sparse saplings/medium), or meadow (about 1% chance of a giant lone oak).
- Rejected if near the edge, near spawn, near a lake, on shore, on uneven ground (>2 m rise within 2 m), or too close to another crown.

**Growing an oak** (deterministic per tree index)
- Trunk: a footprint 1 m wide (2 m for big/giant oaks). Each column fills from its own ground up to a shared top.
- Limbs: 2–5 random walks outward and upward from near the trunk top in 0.5 m steps, stamping bark cubes about 1 m thick that taper at fine block sizes.
- Crown: a central blob plus one at each limb tip. Each is a squashed ellipsoid (height 0.62 × radius) with a noisy edge threshold, so the edges look bitten. Leaves are lighter on top and darker underneath.
- Voxels go into a `Dictionary` keyed by `Vector3i`, then get meshed per chunk with face culling against other tree voxels and the ground.

**Flowers**
- One pass over all columns. Habitat is chosen by distance to the lake edge (shore band), shade (column under any leaf voxel), or meadow.
- Meadow species come from cellular-noise patches, with about 12% strays.
- Density is per m² (`roll / block_area`), so it doesn't depend on block size.
- Each species mesh is a few small boxes built in code. Instances are batched per species per 64 m region into `MultiMesh`, with visibility-range fade.
- `sway.gdshader` bends vertices by `y²` with a per-instance phase and slow rolling gusts. It also converts sRGB vertex colours to linear.

## Player (`player.gd`)

- `CharacterBody3D`. Input actions are created in code (`_ensure_input_actions`) and bound by both physical and logical keycode.
- Movement is velocity lerp towards the target speed; gravity, hop, and a 50° `floor_max_angle` so 45° steps are walkable.
- Falls below y = −30 respawn at `spawn_point()`.

## Determinism

Everything is driven by `world_seed`: `RandomNumberGenerator` seeds and `FastNoiseLite` seeds are offsets of it. Per-block colour and flower jitter use an integer hash of grid coordinates. So a seed plus a block size always gives the same world.

## Known limits / ideas

- No greedy meshing yet: every visible block face is its own quad. Merging flat runs would cut triangles 3–5× and make small block sizes cheap.
- The whole world is built at once (no streaming); 256 m is comfortable.
- Tree crowns are walk-through; a disc hitting leaves is future work (phase 4).
- Over some VNC setups, held keys arrive as instant taps, so WASD won't move you (N still works). An auto-walk toggle is a candidate fix.
