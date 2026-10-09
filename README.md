# discwalk

A voxel walking sim through a generated glacial landscape (kettle lakes, rolling till, a moraine at the world's edge), with disc golf eventually. A playful nod to Discworld.

Built with **Godot 4.7** in plain GDScript. There are no native plugins or C#, so the same project runs on Linux, macOS and Windows.

Design + roadmap: Henon ticket `0002` (`zippychirps/tickets/0002-discwalk-voxel-godot-game.md`).

**Docs:** [Configuration](docs/CONFIG.md) · [Architecture](docs/ARCHITECTURE.md) · [Development](docs/DEVELOPMENT.md)

![Oak grove with lupine and coneflowers](docs/screenshot-oak.png)

## Play

1. Install Godot 4.7.x (standard build, not .NET): <https://godotengine.org/download>
   - **macOS:** download, unzip, drag `Godot.app` to Applications.
   - **Linux (this box):** already at `../tools/godot/Godot_v4.7.2-stable_linux.x86_64`.
2. Open Godot → **Import** → pick this folder's `project.godot` → **Run** (F5).

Or from a terminal:

```sh
# macOS
/Applications/Godot.app/Contents/MacOS/Godot --path /path/to/discwalk
# this Linux box
../tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path .
```

### Controls

| Key | Action |
|---|---|
| WASD / arrows | walk |
| Mouse | look |
| Shift | stroll faster |
| Space | hop |
| N | roll a brand-new world |
| Esc | free the mouse (click to grab it again) |

### Finer blocks (optional)

Voxel size is configurable. The default is 1 m blocks. For a finer, smoother world (same landscape, more detail). 0.25 looks great on a Mac but takes ~11 s to build:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /path/to/discwalk -- --block-size=0.25
```

![1 m blocks (left) vs 0.5 m blocks (right), same seed](docs/screenshot-blocksize-compare.png)

See [docs/CONFIG.md](docs/CONFIG.md) for every knob and the cost trade-offs.

## How the world works

`scripts/terrain.gd` builds everything from one seed:

1. **Till plain:** two layers of simplex noise (hills + long drumlin-ish swells) make a height grid.
2. **Moraine:** the edge of the world rises into a ridge so it feels enclosed.
3. **Kettles:** a few round bowls are pressed into the ground (kept clear of spawn and of each other).
4. **Blocks:** heights snap to whole blocks (1 m by default, see `block_size`). Each 32 m chunk becomes one **greedy-meshed** mesh: only visible faces, with flat same-coloured stretches merged into big rectangles. Per-block colour variation is added in a shader.
5. **Lakes:** each kettle fills with water up to just below its lowest rim, with sandy shores and a muddy bed.
6. **Oaks** (`scripts/flora.gd`): each tree is grown voxel by voxel from its own seed: a stout trunk (2 m wide for big ones), 2–4 crooked limbs reaching outward, and a broad crown of squashed, noise-bitten leaf blobs. Low-frequency noise splits the land into groves and open meadows (Michigan oak openings), with the odd giant lone oak out in a field. No trees in lakes, on shores, on steep ground, or at spawn. Trunks are solid and crowns are walk-through.
7. **Wildflowers:** little voxel plants, drawn with MultiMesh and swaying in a wind shader (`shaders/sway.gdshader`). The species depends on habitat: blue flag iris and marsh marigold by the water, trillium in oak shade, and patches of black-eyed Susan, purple coneflower, wild lupine and butterfly weed in the meadows.
8. **Collision:** a smooth heightmap runs through the block centres. One-block steps feel like gentle ramps, and cliffs of two or more blocks act as walls.

## Dev tools

```sh
G=../tools/godot/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path . --script res://tools/smoke_test.gd      # world builds, walker lands: PASS/FAIL
$G --path . --script res://tools/screenshot.gd -- /tmp/shots    # renders a few PNG views (needs a display)
$G --headless --path . --script res://tools/smoke_test.gd -- --block-size=0.5   # same, finer blocks
```

More in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Roadmap

- [x] **1. Walker + generated voxel terrain + kettle lakes**
- [x] **2. Oaks + wildflowers** (flowers pulled forward from phase 3)
- [x] **2.5 Configurable voxel size** (`--block-size`) + docs
- [x] **Greedy meshing** (about 5× fewer triangles; 0.25 m blocks are now comfortable)
- [ ] Auto-walk toggle (helps over VNC, where held keys arrive as taps)
- [ ] 3. Wind grass (instanced voxel tufts, reusing the flower sway shader)
- [ ] 4. Disc golf 🥏 (rigid-body disc, lift/drag/fade, throw gesture)
- [ ] 5. Polish: day cycle, ambient sound, chunk streaming for bigger worlds
