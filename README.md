# discwalk

A voxel walking sim through a generated glacial landscape (kettle lakes, rolling till, a moraine at the world's edge), with disc golf eventually. A playful nod to Discworld.

Built with **Godot 4.7** in plain GDScript. There are no native plugins or C#, so the same project runs on Linux, macOS and Windows.

Design + roadmap: Henon ticket `0002` (`zippychirps/tickets/0002-discwalk-voxel-godot-game.md`).

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

## How the world works

`scripts/terrain.gd` builds everything from one seed:

1. **Till plain:** two layers of simplex noise (hills + long drumlin-ish swells) make a height grid.
2. **Moraine:** the edge of the world rises into a ridge so it feels enclosed.
3. **Kettles:** a few round bowls are pressed into the ground (kept clear of spawn and of each other).
4. **Blocks:** heights snap to whole 1 m blocks. Each 32×32 chunk becomes one mesh that only has the visible faces.
5. **Lakes:** each kettle fills with water up to just below its lowest rim, with sandy shores and a muddy bed.
6. **Collision:** a smooth heightmap runs through the block centres. One-block steps feel like gentle ramps, and cliffs of two or more blocks act as walls.

## Dev tools

```sh
G=../tools/godot/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path . --script res://tools/smoke_test.gd      # world builds, walker lands: PASS/FAIL
$G --path . --script res://tools/screenshot.gd -- /tmp/shots    # renders a few PNG views (needs a display)
```

## Roadmap

- [x] **1. Walker + generated voxel terrain + kettle lakes**
- [ ] 2. Trees (rule-based scatter: not in water, not on steep slopes)
- [ ] 3. Wind grass (instanced voxel tufts + sway shader)
- [ ] 4. Disc golf 🥏 (rigid-body disc, lift/drag/fade, throw gesture)
- [ ] 5. Polish: day cycle, ambient sound, chunk streaming for bigger worlds
