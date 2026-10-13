# Controls

How every input works today, keyboard + mouse and controller side by side.

> Code: bindings live in `scripts/player.gd` (`_ensure_input_actions`). Handlers: `scripts/player.gd` (walk, look, jump, run), `scripts/throw_setup.gd` (throw setup), `scripts/thrower.gd` (throws, toggles), `scripts/main.gd` (world, clouds, HUD size). The throw HUD itself is specced in [THROW-HUD.md](THROW-HUD.md).
> Controller: Xbox-style (tested with an Xbox Series X|S pad). Any connected controller works. Mapping notes: `scratch/controller.md` (not committed).

The mouse (or right stick) only ever looks. Where you look is where the throw goes: left/right is the direction, and how high you look is the launch angle (the horizon dial shows it). The throw setup carries over from throw to throw.

## Walk and look

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Walk | WASD | Left stick |
| Look / aim | Mouse | Right stick (squared response: small pushes aim finely; full push = 3 rad/s) |
| Faster | Shift (hold) | View button: **toggle** run on/off (stays on until pressed again; also applies to keyboard walking) |
| Jump | Space (fixed hop, `jump_velocity` 5 m/s ≈ 1.3 m) | — |
| Crouch | — | — |
| Free the mouse | Esc (click to grab it again) | — |

## Set up the throw

A tap moves one fine step (0.5° nose, 1° hyzer, 0.5 m/s speed, 2 rad/s spin). Holding repeats, faster the longer you hold.

| Action | Keyboard | Controller |
|---|---|---|
| Nose up / down | ↑ / ↓ | D-pad ↑ / ↓ |
| Tilt: the edge on that side drops (backhand ← = hyzer; forehand mirrored) | ← / → | D-pad ← / → |
| Release speed (discs **and** cubes) | Shift + ↑ / ↓ | **RB** (hold) + D-pad ↑ / ↓ |
| Spin (only when unlocked) | Shift + ← / → | **RB** (hold) + D-pad ← / → |
| Next / previous disc | Tab / Shift+Tab | **LB** (hold) + D-pad → / ← (one disc per press, no repeat) |
| Backhand ↔ forehand | H | **LB** tap (fires on release, and only if the D-pad wasn't used during the hold) |
| Spin lock / unlock (locked = spin follows speed) | X | — |
| Reset to flat (nose 0, hyzer 0) | R | — |

D-pad pages: plain = nose/tilt, RB held = speed/spin, LB held = disc (↑ / ↓ unused). LB + RB held together: the D-pad does nothing.

## Throw

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Throw the disc | Left click / Enter | A |
| Throw an orange cube (same speed) | Right click | B |
| Launch yourself with your last throw, while it's still moving | L | Y |
| Collect: every disc rolls home to you | C | X |

## Toggles (lamps in the HUD)

| Action | Keyboard | Controller |
|---|---|---|
| Chase view (camera follows each throw) | V | Right stick click (the look stick) |
| Goto (moved to each throw once it stops; "warp" in code) | G | Left stick click (the walk stick) |
| Paths + rest beams | P | Share button |

## World and display

| Action | Keyboard | Controller |
|---|---|---|
| Hide / show the throw HUD and help text | U | — |
| HUD smaller / bigger | - / = (also keypad; `--ui-scale=` at launch) | — |
| Clouds on / off | K | — |
| New world | N | — |

## Controller inputs still free

| Input | Notes |
|---|---|
| LT, RT | Analog. `scratch/controller.md` has them "saved for the dynamic throw" |
| Menu (Start) | |
| LB (hold) + D-pad ↑ / ↓ | |
| Xbox (Guide) | macOS may grab it |

## Not on the controller yet

Jump, spin lock (X), reset flat (R), hide HUD (U), HUD size, clouds (K), new world (N), free mouse (Esc).

## Notes

- Keys are bound by physical **and** logical keycode, so WASD stays put on other layouts and remote input (VNC, Screen Sharing) still works. Over some VNC setups held keys arrive as taps, so walking won't work there.
- Stick and trigger actions use a 0.2 deadzone.
- `-- --debug-keys` prints every key event to stdout ([CONFIG.md](CONFIG.md)).
