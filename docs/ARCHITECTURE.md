# Architecture

A short tour of how discwalk is put together. It is written for "future us" opening the project after a break.

## Files

```
project.godot            Godot project settings (window, physics tick, MSAA)
scenes/main.tscn         The one scene: sky/environment, sun, Terrain, Player, HUD
scripts/main.gd          Glue: spawns the player, HUD text, N = new world, --debug-keys
scripts/terrain.gd       Height field, kettle lakes, chunk meshes, water, collision
scripts/flora.gd         Oaks (voxel trees) and wildflowers (MultiMesh)
scripts/voxel_mesh.gd    Greedy face merging + quad/mesh helpers (shared)
scripts/player.gd        First-person walker: input bindings, movement, head bob
shaders/voxel.gdshader   Terrain + tree shading: base colour + per-block jitter
shaders/sway.gdshader    Wind sway for flowers (and grass, later)
tools/smoke_test.gd      Headless PASS/FAIL check
tools/screenshot.gd      Renders PNG views incl. one portrait per oak form (needs a display/GPU)
tools/tree_gallery.gd    Flat-ground lineup of every oak form, for tuning trees
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
5. **Chunk meshes** (greedy, see below):
   - Tops: one row per z. Faces with the same height and kind (grass, sand, mud) merge into rectangles.
   - Sides: for each direction and each column line, a column's exposed side is split into soil-layer runs (sand, turf, dirt, stone, by metres below the surface). Identical runs on neighbouring columns merge.
   - Hidden faces are never emitted.
6. **Water**: one thin transparent cylinder per lake.
7. **Collision**: a `HeightMapShape3D` with one sample per column at block centres, plus 4 invisible boundary walls. Smooth collision means one-block steps behave like 45° ramps (the player allows 50°), and two-block steps are walls.
8. **Flora**: `flora.build(terrain)`, described next.

## Flora (`flora.gd`)

**Tree placement**
- Candidate spots on a jittered `grove_spacing` grid (metres).
- Grove noise picks the zone: grove (dense, big/medium), grove edge (sparse saplings/medium), or meadow (about 1% chance of a giant lone oak).
- Rejected if near the edge, near spawn, near a lake, on shore, on uneven ground (>2 m rise within 2 m), or too close to another crown.

**Oak forms.** Each tree gets a size class (sapling / medium / big / giant) and a **form**, picked by `_pick_form()` from its size and how deep in a grove it stands:

| Form | Where | Shape |
|---|---|---|
| `spreading` | lone giants, open groves | short massive trunk (2–4 m), 4–6 long low limbs (8–32°) that curve up at the ends, 3 levels of branching, wide crown |
| `tall` | deep in groves (reaching for light) | tall clear trunk (5.5–9.5 m), steep limbs near the top, compact high crown |
| `forked` | anywhere | trunk splits into 2 (sometimes 3) leaders part way up, each with its own limbs |
| `leaning` | anywhere | trunk tilts 12–24°, so the crown reaches out over one side |
| `sapling` | grove edges | thin stem (1.6–3.6 m), a few twiggy branches |

All the numbers live in the `FORMS` and `TRUNK_R` tables at the top of the oak section in `flora.gd`. Crown radius also varies ±20–25% per tree.

**Growing an oak** (deterministic per tree index, all in metres)
- **Skeleton**: the trunk is a tapering tube with a root flare at the base, leaning per form. Primary limbs spiral up the top part of the trunk (golden-angle spacing). Then `_branch()` recurses: each branch wanders slightly, curves upward (`upcurve`), sprouts 0–2 side branches, and forks into 2–3 children at its tip, until `depth` runs out.
- **Bark**: spheres stamped every ~0.4 m along each branch, with radius tapering from trunk to twig. Spheres thinner than about half a block become single voxels, so twigs are 1-block lines at coarse sizes and properly tapered at 0.25 m.
- **Leaves**: every branch tip gets a leaf cluster sitting slightly above the twig end (so limbs show from underneath), plus an occasional smaller puff part way along. Each cluster is a squashed ellipsoid with a noisy, bitten edge. Shading mixes the cluster's own top/bottom with the whole crown's height, so puffs look rounded but the crown is still lit from above and dark underneath. Leaf greens are a per-tree mix of four oak greens.
- **Dead limbs**: about 7% of primary limbs on bigger trees are bare and grey, with no leaves.
- Voxels go into a `Dictionary` keyed by `Vector3i`. Each chunk is then greedy-meshed: visible faces (culled against other tree voxels and the ground) are grouped by direction and plane and merged by colour. Leaf shading is quantised into 5 bands so neighbouring leaves can merge.

**Flowers**
- One pass over all columns. Habitat is chosen by distance to the lake edge (shore band), shade (column under any leaf voxel), or meadow.
- Meadow species come from cellular-noise patches, with about 12% strays.
- Density is per m² (`roll / block_area`), so it doesn't depend on block size.
- Each species mesh is a few small boxes built in code. Instances are batched per species per 64 m region into `MultiMesh`, with visibility-range fade.
- `sway.gdshader` bends vertices by `y²` with a per-instance phase and slow rolling gusts. It also converts sRGB vertex colours to linear.

## Greedy meshing + the voxel shader

Without merging, every visible block face is its own quad. At 0.25 m blocks that's about 4M terrain triangles. With greedy meshing (`voxel_mesh.gd`), coplanar neighbouring faces facing the same way with the same base colour become one rectangle:

1. Faces in a plane are grouped into rows (by their `v` coordinate) and packed as ints `(u << 20) | colour_id`.
2. `merge_rows()` sorts each row and joins adjacent same-colour faces into runs `(u0, u1, colour)`.
3. A run that appears identically on the next row extends a rectangle; otherwise the rectangle is closed.

It's linear in the number of faces, and close to optimal for terrain and leaves. Result at 1 m blocks: terrain 246k → 50k triangles, trees 96k → 54k. At 0.25: 3.9M → 737k and 1.6M → 712k.

**Colour jitter moved to the GPU.** A merged quad spans many blocks, so per-block colour variation can't live in vertex colours any more. Instead:
- vertex colour rgb = the block's base colour (sRGB)
- vertex colour alpha = jitter strength (turf 0.10, grass 0.12, stone 0.15, leaves 0.14, bark 0.25, …)
- `voxel.gdshader` steps half a block back along the normal to find which block each pixel belongs to, hashes that block's integer coordinates, and darkens the colour by `hash × strength`.

Meshes are in block units, so this works at any block size.

Caveat: greedy meshes have T-junctions (a big quad's edge meeting several small ones). On some GPUs that can show as rare single-pixel sparkles along seams. It hasn't been visible so far.

## Player (`player.gd`)

- `CharacterBody3D`. Input actions are created in code (`_ensure_input_actions`) and bound by both physical and logical keycode.
- Movement is velocity lerp towards the target speed; gravity, hop, and a 50° `floor_max_angle` so 45° steps are walkable.
- Falls below y = −30 respawn at `spawn_point()`.

## Determinism

Everything is driven by `world_seed`: `RandomNumberGenerator` seeds and `FastNoiseLite` seeds are offsets of it. Per-block colour and flower jitter use an integer hash of grid coordinates. So a seed plus a block size always gives the same world.

## Known limits / ideas

- World build time at small block sizes is dominated by GDScript tree voxel growth and meshing. Since the branching oaks, that's about 35 s + 15 s on the T480 at 0.25, with ~3.6M tree voxels and ~1.7 GB RAM. Options if it ever matters: PackedArray voxel storage instead of a Dictionary, building on a thread with a loading screen, or building chunks lazily.
- The whole world is built at once (no streaming); 256 m is comfortable.
- Tree crowns are walk-through; a disc hitting leaves is future work (phase 4).
- Over some VNC setups, held keys arrive as instant taps, so WASD won't move you (N still works). An auto-walk toggle is a candidate fix.
