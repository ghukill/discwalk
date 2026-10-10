# discwalk

A voxel walking sim through a generated glacial landscape (kettle lakes, rolling till, a moraine at the world's edge), with disc golf eventually. A playful nod to Discworld.

Built with **Godot 4.7** in plain GDScript. There are no native plugins or C#, so the same project runs on Linux, macOS and Windows.

Design + roadmap: Henon ticket `0002` (`zippychirps/tickets/0002-discwalk-voxel-godot-game.md`).

**Docs:** [Configuration](docs/CONFIG.md) · [Architecture](docs/ARCHITECTURE.md) · [Development](docs/DEVELOPMENT.md) · [Disc flight plan](docs/DISC-FLIGHT-PLAN.md)

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
| T | **throw panel** (lower right): pick a disc, set speed, launch offset, nose, hyzer/anhyzer and spin, press **Throw**. A real flying disc leaves where you're looking, left/right **and up/down** (right-hand backhand); the launch offset (0° by default) tilts it above or below your view. `launch +12°` under the crosshair shows the angle you'd throw at. T again closes it |
| H / J | heading (compass) / horizon (attitude) dials on or off, top right. The orange chevron on the horizon dial is your launch angle (view + offset) |
| 1–9, 0 | set block power 1–10 (0 = 10), shown top-right as `Velocity: #` |
| Left click | fire an orange **block** at the current power (the original cannon, kept for fun) |
| V | **follow cam**: chase your last disc through its flight and ground play. Snaps back to you once it fully stops (or press V again) |
| P | **flight paths on/off** (starts on; also a checkbox in the throw panel, state shown top-right). On: every disc throw leaves a trail of little cubes in its own colour (bright in the air, smaller and dimmer for skips and rolls). Off: they all drift down and go *poof* on the ground, and new throws leave none until P again |
| F | fetch: jump to your last disc. **If it's still flying, you fly with it** (you take on its speed and direction until you land) |
| B | toggle the beams of light over resting discs (status top-right) |
| C | **collect**: every disc rolls home to you, slow at first and then faster and faster. Trunks and cliffs block them unless they have the momentum |
| N | roll a brand-new world |
| K | clouds on/off (launch with `-- --no-clouds` to start without them) |
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
6. **Oaks** (`scripts/flora.gd`): each tree is grown from its own seed as a branching skeleton. A tapering trunk with a root flare carries spiralling limbs, and those recurse into side branches, forks and twigs, with a leaf cluster on every tip. Five forms: wide **spreading** lone oaks, **tall** grove oaks reaching for light, **forked**, **leaning**, and **saplings**. There are occasional bare dead limbs, and every tree mixes its own shade of green. Low-frequency noise splits the land into groves and open meadows (Michigan oak openings), with the odd giant lone oak out in a field. No trees in lakes, on shores, on steep ground, or at spawn. Trunks are solid and crowns are walk-through.
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

Done:
- [x] **1. Walker + generated voxel terrain + kettle lakes**
- [x] **2. Oaks + wildflowers**: branching oaks in 5 forms, habitat-based wildflowers with wind sway
- [x] **Configurable voxel size** (`--block-size`) + docs
- [x] **Greedy meshing** (about 5× fewer triangles; 0.25 m blocks are comfortable)
- [x] **Disc throwing, step 1**: a block fired from you that bounces off ground and trunks, clatters through branches, gets swallowed by leaves, and floats in lakes. Power keys, fetch (ride a flying disc!), beam toggle, collect (discs roll home).
- [x] **Disc flight, step 2**: flat pixel discs with lift, drag and gyroscopic turn/fade (`disc_model.gd`), four disc tables, a lower-right throw panel (T). Checked against shotshaper (`tools/flight_test.gd`).

Next (pick any):
- [x] **Follow cam (V)**: chase camera behind the disc, hands back once it stops
- [x] **Flight paths**: voxel trail per throw, own colour, dimmer on the ground; P toggles; off = they fall and poof
- [ ] Picture-in-picture follow cam
- [ ] Wind (static vector to start), forehand toggle in the panel, more discs / our own coefficient tables (replace the GPL shotshaper ones, see `data/discs/README.md`)
- [ ] Discs resting in trees; baskets
- [ ] **Wind grass**: instanced voxel tufts, reusing the flower sway shader
- [ ] More tree variety (tuning, species, autumn)
- [ ] Auto-walk toggle (helps over VNC, where held keys arrive as taps)

Explore later:
- [ ] **Export + import worlds**: write a world to a file (seed + settings, plus anything hand-edited or placed, e.g. discs, baskets) and load it back. That's the foundation for **pre-made worlds** shipped as files you pick at startup, e.g. a **flat distance world**: long and narrow, no plants, no lakes, distance markings in the ground
- [ ] **Game controller support**: left stick walk, right stick look, triggers/buttons for throw, follow cam, paths, fetch; the throw panel navigable with the d-pad
- [ ] **Single-file builds**: Godot export for Linux (one binary with the game data embedded) and macOS (a universal .app, zipped), built headless on the T480
- [ ] **Distance throwing zone**: a field marked with distance lines in the ground, either near one edge of every world (e.g. the west edge) or, better, its own pre-made world (which opens the door to hand-made/pre-made worlds generally)
- [ ] Background/threaded tree building with a grow-in animation
- [ ] Bigger worlds; infinite streaming world (region-local lakes/trees, chunks built as you walk)
- [ ] Polish: day cycle, ambient sound
