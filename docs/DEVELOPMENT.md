# Development

## Machines

| Where | What | Notes |
|---|---|---|
| **T480** (Linux, headless) | Main dev box. Repo at `~/.henon/instances/zippychirps/discwalk`. Godot at `../tools/godot/Godot_v4.7.2-stable_linux.x86_64`. | Real GPU (Intel UHD 620) on `DISPLAY=:0` (~30 fps at 720p). VNC `:1` is software-rendered (llvmpipe, ~3–10 fps), so only use it for previews. |
| **Bosworth** (Mac, M1 Pro) | Playtest box. Repo cloned at `~/projects/discwalk`, Godot at `~/Applications/Godot.app`. | Metal, 60 fps capped (~450 uncapped). |

Launch on Bosworth from the T480:

```sh
ssh commander@100.93.7.9 'cd ~/projects/discwalk && git pull -q && open -n ~/Applications/Godot.app --args --path ~/projects/discwalk'
# finer blocks:
ssh commander@100.93.7.9 'open -n ~/Applications/Godot.app --args --path ~/projects/discwalk -- --block-size=0.5'
# stop:
ssh commander@100.93.7.9 'pkill -f Godot.app/Contents/MacOS/Godot'
```

Over SSH, macOS won't allow `screencapture` (no Screen Recording permission), so take screenshots on the T480's `:0` instead.

## Checks before committing

```sh
G=../tools/godot/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path . --script res://tools/smoke_test.gd                      # default world
$G --headless --path . --script res://tools/smoke_test.gd -- --block-size=0.5  # fine blocks
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/screenshot.gd -- /tmp/shots
```

The smoke test passes when:
- all chunks are built
- at least one lake exists
- the player is standing on the ground after 3 s
- there are more than 10 oaks
- at least 5 flower species appear

It prints counts (terrain/tree triangles, oaks by size, voxels, flowers per species) and flora build timings, which are handy for spotting regressions. At the default settings, seed 1848 gives 50,208 terrain triangles, 54,380 tree triangles, 295 oaks and 27,345 tree voxels.

Screenshot views: oak, meadow, spawn, lakeshore, overview, plus one portrait per oak form (`form_spreading`, `form_tall`, …).

For tree work, the gallery is quicker. It puts one row per form, three trees each, on flat ground, and shoots each row plus a look up from under the biggest tree:

```sh
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/tree_gallery.gd -- /tmp/gallery --block-size=0.25
```

To check frame rate: `DISPLAY=:0 $G --path . --resolution 1280x720 --print-fps --quit-after 600`.

## Conventions

- Plain GDScript, typed where it helps (Godot 4.7 can't infer types from `Dictionary`/`Array` element access, so annotate those: `var d: float = ...`).
- Settings are in metres; grid work is in blocks (see [ARCHITECTURE.md](ARCHITECTURE.md#units-metres-vs-blocks)).
- Keep things deterministic from `world_seed`: no unseeded `randf()` in generation.
- New user-facing knobs go in [CONFIG.md](CONFIG.md).
- Commit messages: `area: what changed` with a short body; phase landings as `phase N: ...`.

## Git

- GitHub: <https://github.com/ghukill/discwalk> (`main`).
- Tags: `checkpoint-1` = phase 1.
- Bosworth pulls over HTTPS (works while the repo is public).
