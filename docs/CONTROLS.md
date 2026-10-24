# Controls

How every input works today, keyboard + mouse and controller side by side.

> In game: press **?** (or open the menu, Esc / Menu on a controller, → Controls) for the same tables as an overlay (`scripts/controls_panel.gd`; keep it in step with this file).
>
> Code: bindings live in `scripts/player.gd` (`_ensure_input_actions`). Handlers: `scripts/player.gd` (walk, look, jump, crouch, run), `scripts/throw_setup.gd` (throw setup), `scripts/thrower.gd` (throws, toggles), `scripts/course_round.gd` (Course Play: overview, skipping the walk), `scripts/menu.gd` (the menu), `scripts/main.gd` (world, clouds, HUD size). The throw HUD itself is specced in [THROW-HUD.md](THROW-HUD.md).
> Controller: Xbox-style (tested with an Xbox Series X|S pad). Any connected controller works. Mapping notes: `scratch/controller.md` (not committed). Tests: `tools/controls_test.gd` (controller pages, crouch), `tools/hud_test.gd` (throw setup keys).

## Controller at a glance

The two bumpers are pages: hold one and the D-pad (and one face button) do something else.

| Input | Plain | RB held | LB held |
|---|---|---|---|
| A | jump | (jump) | (jump) |
| B | throw the disc | throw a cube | hole overview (Course Play) |
| X | crouch / stand (toggle) | (crouch) | collect |
| Y | launch yourself | — | shot circle |
| D-pad ↑ / ↓ | nose | release speed | ↑ reset to flat · ↓ spin lock |
| D-pad ← / → | tilt (hyzer / anhyzer) | spin | previous / next disc |
| Tap alone | — | nothing | backhand ↔ forehand |

- LB page actions fire once per fresh press (no repeat); a D-pad already held when LB goes down doesn't count.
- LB tap flips the hand on release, and only if nothing else was pressed during the hold.
- LB + RB held together: the D-pad does nothing.
- Sticks: walk / look; clicking them toggles goto (left) and chase view (right). View = run toggle, Menu = the game menu (D-pad + A to pick, B to go back), Share = paths.

The mouse (or right stick) only ever looks. Where you look is where the throw goes: left/right is the direction, and how high you look is the launch angle (the horizon dial shows it). The throw setup carries over from throw to throw.

## Walk and look

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Walk | WASD | Left stick |
| Look / aim | Mouse | Right stick (squared response: small pushes aim finely; full push = 3 rad/s) |
| Faster | Shift (hold) | View button: **toggle** run on/off (stays on until pressed again; also applies to keyboard walking) |
| Jump | Space (fixed hop, `jump_velocity` 5 m/s ≈ 1.3 m) | A |
| Crouch / stand (toggle) | Tab | X |
| Menu (pauses; frees the mouse) | Esc | Menu (Start) |

## Set up the throw

A tap moves one fine step (0.5° nose, 1° hyzer, 1 mph speed — or 0.5 m/s if you switch the readout with **I** — 2 rad/s spin). Holding repeats, faster the longer you hold.

| Action | Keyboard | Controller |
|---|---|---|
| Nose up / down | ↑ / ↓ | D-pad ↑ / ↓ |
| Tilt: the edge on that side drops (backhand ← = hyzer; forehand mirrored) | ← / → | D-pad ← / → |
| Release speed (discs **and** cubes) | Shift + ↑ / ↓ | **RB** (hold) + D-pad ↑ / ↓ |
| Spin (only when unlocked) | Shift + ← / → | **RB** (hold) + D-pad ← / → |
| Next / previous disc | E / Q | **LB** (hold) + D-pad → / ← |
| Backhand ↔ forehand | H | **LB** tap |
| Reset to flat (nose 0, hyzer 0; speed and spin stay) | R | **LB** (hold) + D-pad ↑ |
| Spin lock / unlock (locked = spin follows speed) | X | **LB** (hold) + D-pad ↓ |
| Speed readout in **mph** / **m/s** | I | — |
| **Aim arc**: where the throw you have set up would land | T | — |
| **Basket beam + arrow**: next / previous basket (Free Play; in Course Play it follows the hole) | B / Shift+B | — |

## Throw

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Throw the disc | Left click / Enter | B |
| Throw an orange cube (same speed) | Right click | **RB** (hold) + B |
| Launch yourself with your last throw, while it's still moving (stands you up) | L | Y |
| Collect: every disc rolls home to you (and basket confetti flies in) | C | **LB** (hold) + X |

## Toggles (lamps in the HUD)

| Action | Keyboard | Controller |
|---|---|---|
| Chase view (camera follows each throw) | V | Right stick click (the look stick) |
| Goto (walked to each throw once it stops; "warp" in code) | G | Left stick click (the walk stick) |
| Paths + rest beams | P | Share button |
| Shot circle (at your lie, held within 1 m of it; a faint ring shows it) | O | **LB** (hold) + Y |

## Course Play

| Action | Keyboard | Controller |
|---|---|---|
| Hole overview (camera flies up over tee, basket and you; again to come back) | M | **LB** (hold) + B |
| Skip the walk to the next tee, or goto's walk to your disc | any move key, Space, or a throw | left stick, A, or B |

## World and display

| Action | Keyboard | Controller |
|---|---|---|
| The menu: Resume, Free Play, Course Play, Controls, Quit (1 / 2 pick a mode) | Esc | Menu (Start) |
| Show / hide the controls overlay | ? (Shift + /) | menu → Controls |
| Hide / show the throw HUD and the "Press ? for controls" hint | U | — |
| HUD smaller / bigger | - / = (also keypad; `--ui-scale=` at launch) | — |
| Clouds on / off | K | — |
| New world (course) | N | — |

## Crouching

One height, toggled (Tab / X), no need to hold. Crouched: eyes drop 0.65 m, the body is 1.1 m tall instead of 1.8 m (you fit under low branches), and you walk at 2 m/s whatever Shift or the run toggle say.

- **Standing needs headroom.** Toggle off under a canopy or an overhang and you stay down; you stand on your own as soon as there's room.
- **Jump from a crouch** stands you up and hops, if there's room. If there isn't, nothing happens.
- **Launch (L / Y)** and respawning stand you up.

## Controller inputs still free

| Input | Notes |
|---|---|
| LT, RT | Analog. `scratch/controller.md` has them "saved for the dynamic throw" |
| RB held + Y | |
| LB held + A | Works as plain A for now |
| Xbox (Guide) | macOS may grab it |

## Not on the controller yet

Hide HUD (U), HUD size, clouds (K), new world (N).

## Notes

- Keys are bound by physical **and** logical keycode, so WASD stays put on other layouts and remote input (VNC, Screen Sharing) still works. Over some VNC setups held keys arrive as taps, so walking won't work there.
- Stick and trigger actions use a 0.2 deadzone.
- `-- --debug-keys` prints every key event to stdout ([CONFIG.md](CONFIG.md)).
