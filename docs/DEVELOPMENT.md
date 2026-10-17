# Development

## Standalone macOS app (Apple Silicon and Intel)

This is a GDScript project: **do not run SCons in this repo**. SCons compiles the Godot engine, not discwalk. Export the project with Godot instead. The `macOS` preset in `export_presets.cfg` makes a Universal 2 `.app` (native ARM64 on Apple Silicon, x86_64 on Intel) using an ad-hoc signature for local testing. It bundles the disc JSON tables but excludes docs, tools, and previous builds. `project.godot` enables ETC2/ASTC texture import, which Godot requires for ARM64 exports.

1. Install **Godot 4.7.2 standard** (not .NET) and its **matching 4.7.2 export templates**. In the editor, use **Editor → Manage Export Templates → Download and Install**. The templates are installed per user, not in this repo. Alternatively, download `Godot_v4.7.2-stable_export_templates.tpz` from the [official release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) and extract `templates/macos.zip` and `templates/version.txt` to `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` (the full download is about 1.2 GB; only `macos.zip` is needed afterwards).
2. Set `config/version` in `project.godot` (`"0.1"` initially), then run from the repo root:

   ```sh
   ./tools/build_macos.sh
   # If Godot is installed elsewhere:
   GODOT_BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot" ./tools/build_macos.sh
   ```

   The script imports resources, exports the app, verifies its version, Apple Silicon binary and signature, then packages it with `ditto`. For version `0.1` it creates `builds/v0.1/discwalk.app` and `builds/v0.1/discwalk-v0.1-macos-universal.zip`. Upload the ZIP to a release; the `.app` is for local play. To rebuild the same version, remove that version's `.app` and `.zip` first. Bump `config/version` for the next release; the folder name, ZIP name, and macOS app version all come from it. `builds/` is gitignored, as is the old `build/` output. Godot may also generate `.uid` files when importing for the first time (keep those in version control for stable resource IDs).

   To check without playing, use `builds/v0.1/discwalk.app/Contents/MacOS/discwalk --quit-after 180 -- --block-size=1` (the coarse blocks shorten startup). The `.app` needs no Godot editor installed to run. For a manual export, run `Godot --headless --path . --editor --import`, create an output directory, then run `Godot --headless --path . --export-release macOS path/to/discwalk.app`.

**Distribution:** This preset uses built-in **ad-hoc signing**, not Apple Developer ID signing or notarization. It runs locally, but Gatekeeper may block copies downloaded on another Mac. Public distribution requires a Developer ID certificate, signing, and notarization (see [Godot's macOS export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)). The disc tables are our own (built from published measurements; see `docs/PHYSICS.md`), so no third-party data license applies.

## Checks before committing

```sh
G=../tools/godot/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path . --script res://tools/smoke_test.gd                      # default world (0.25 m blocks, ~1 min)
$G --headless --path . --script res://tools/smoke_test.gd -- --block-size=1    # chunky blocks, quick
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/screenshot.gd -- /tmp/shots
```

Throwing has its own headless check. It throws 4 discs across open ground at powers 2, 5, 8 and 10, one into the biggest oak, and one into a lake. It passes when:
- they all come to rest
- the oak throw touches bark or leaves
- the lake throw splashes
- a sky-high throw you launch yourself with (L) mid-flight hands its velocity to the player, who then keeps pace with it
- P (paths off) hides every beam

```sh
$G --headless --path . --script res://tools/throw_test.gd [-- --block-size=0.5]
```

Disc flight has one. It throws real flying discs over an empty flat floor and compares carry and drift with a full 6-DOF integration of Hummel's equations, wobble and all (within 5% carry, 2.5 m drift), for 8 throws covering all 7 discs. That checks the game's quasi-steady shortcut and catches changes to the maths or the disc tables. It also checks each disc's character: the overstable Erratic fades even thrown anhyzer, the understable Till turns over flat, the Moraine hyzer-flips long, the Kettle putter is short and straight at putting speed, a driver out-carries the putter, a forehand mirrors a backhand, more hyzer bends the flight further, spin bleeds off. Last, it throws from spawn in the real world with the follow cam on, and checks the disc lands and rests, the camera stays close to it all the way, and the view goes back to the walker afterwards.

```sh
$G --headless --path . --script res://tools/flight_test.gd [-- --block-size=0.5]
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/flight_shots.gd -- /tmp/flight_shots   # HUD, follow cam in flight/on the ground, handed back
```

The disc tables are generated, and the reference numbers come from our own 6-DOF Hummel integrator (~1.5 min; 256 attitude substeps per tick). If you change the tables or the maths on purpose, rebuild and paste the new numbers into `REFERENCE` in `tools/flight_test.gd`:

```sh
python3 tools/discs/build_tables.py                       # data/discs/discwalk/*.json
uv run --with numpy python tools/discs/hummel_reference.py
```

Landing has a stress test: 48 discs from spawn in every direction, mixed discs, speeds, angles and hyzer. It fails if any ends up under the ground or lost:

```sh
$G --headless --path . --script res://tools/landing_test.gd [-- --block-size=0.5]
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/paths_shots.gd -- /tmp/paths_shots   # flight paths + the P fall/poof
```

Ground play (skips and skids) has a tuning check: 48 throws over flat ground, reporting how far discs go after first contact. It passes when that averages 10–25 m:

```sh
$G --headless --path . --script res://tools/skip_test.gd
```

The chase view (V) / goto (G) toggles and launch (L) have their own, run as a string of little scenes from spawn: view only, warp only, both, launch mid-flight (overrides both, no warp after), L after the throw stopped (does nothing), L while a disc skids/rolls (still works), toggles off mid-flight, a second throw taking over, collect ignoring the toggles, and P putting beams out with the paths:

```sh
$G --headless --path . --script res://tools/toggles_test.gd [-- --block-size=0.5]
```

The throw setup keys and HUD have one. It presses the real keys (arrows, Shift+arrows, X, R, H, E/Q, Enter, clicks, U, G) and checks the setup values, the hold-to-repeat, that the arrows no longer walk, that throws carry the setup and keep it, and that right click throws a cube at the disc speed:

```sh
$G --headless --path . --script res://tools/hud_test.gd [-- --block-size=1]
DISPLAY=:0 $G --path . --resolution 1600x900 --script res://tools/hud_shots.gd -- /tmp/hud_shots   # hud.png, hud_corner.png, hud_strip.png (five setups)
```

The controller pages and crouching have one. It presses real controller buttons and keys: B throws a disc and RB + B a cube, LB tapped flips the hand, LB + D-pad ↑ / ↓ reset to flat and toggle spin lock, LB + X collects (no crouch, no hand flip), X and Tab crouch (lower capsule and eyes, 2 m/s), A from a crouch stands and hops, and under a roof you stay down until it's gone:

```sh
$G --headless --path . --script res://tools/controls_test.gd [-- --block-size=1]
```

Collecting has one too. It scatters 8 discs around spawn, presses C, and passes if at least 6 make it home and they start slow (under 3 m/s in the first second):

```sh
$G --headless --path . --script res://tools/collect_test.gd [-- --block-size=0.5]
```

Courses and Course Play have one. It checks the nine holes (in order, Basket<n> = hole n, tees a hole's length out, painted, level, dry, clear of baskets), then plays: on hole 1's tee with goto + shot circle on, a cube doesn't count but a disc does, the goto faces the basket and picks the disc up, the circle holds you to 1 m (off = free, on = back round the lie), the overview flies up and back (also LB + B, and LB + Y is the circle), another hole's basket doesn't finish the hole, this one does, then the walk to the next tee and a move key skipping it, the last hole ending the round, and Free Play turning it all off. `course_shots.gd` shoots hole 1 from its tee, the pad from above, the shot circle, the overview and the menu:

```sh
$G --headless --path . --script res://tools/course_test.gd [-- --block-size=1]
DISPLAY=:0 $G --path . --resolution 1280x720 --script res://tools/course_shots.gd -- /tmp/course_shots
```

The smoke test passes when:
- all chunks are built
- at least one lake exists
- the player is standing on the ground after 3 s
- there are more than 10 oaks
- at least 5 flower species appear

It prints counts (terrain/tree triangles, oaks by size, voxels, flowers per species) and flora build timings, which are handy for spotting regressions. At `--block-size=1`, seed 1848 gives 50,208 terrain triangles, 54,380 tree triangles, 295 oaks and 27,345 tree voxels.

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
- `scratch/` is for scratch work you don't commit: sketches, notes, one-off scripts, test output. Git ignores everything in it except its own `.gitignore` and `.gdignore`, and the `.gdignore` keeps Godot from importing or exporting anything in it.

## Git

- GitHub: <https://github.com/ghukill/discwalk> (`main`).
- Tags: `checkpoint-1` = phase 1.
