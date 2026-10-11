# Throw HUD rework (spec)

> **Status:** agreed with Graham, not built yet. Sketch: [mockups/throw-hud-sketch.png](mockups/throw-hud-sketch.png).
> Replaces the T throw panel. Controllers are out of scope for now.

## HUD (one block, lower right)

- **Disc circle**: the disc drawn from slightly behind and above. Left/right tilt shows hyzer/anhyzer. Nose up shows a bit of the underside, plus a small `+3°` readout (first try, iterate). The disc is drawn in the current disc's colour.
- **✋ hand**: right of the circle = backhand, left = forehand.
- **Velocity bar** (left of the pair) and **spin bar** (right). Spin is dotted/dimmed and can't be changed while it's locked (auto spin from speed).
- **Heading dial** and **horizon dial** below. They always show; the horizon chevron = launch angle (= view pitch, no offset).
- **Lamps**: Chase view (V), Goto (G), Paths (P).
- `launch +N°` stays under the crosshair.

## Keys

| Key | Action |
|---|---|
| WASD | walk (arrows no longer walk) |
| Mouse | look, always. Aim = where you look; view pitch is the launch angle |
| Shift | stroll faster |
| Space | hop |
| ↑ / ↓ | nose up / down |
| ← / → | hyzer / anhyzer |
| Shift + ↑ / ↓ | velocity |
| Shift + ← / → | spin (only when unlocked) |
| X | spin lock / unlock |
| R | reset disc to flat (nose 0, hyzer 0) |
| H | backhand ↔ forehand |
| Tab | cycle discs |
| Left click / Enter | throw disc |
| Right click | throw orange cube |
| L | launch yourself with your last throw (disc or cube) |
| V | chase view toggle (discs + cubes) |
| G | goto toggle (was Z warp; discs + cubes) |
| P | paths + beams toggle |
| U | hide / show the whole HUD |
| C | collect |
| N | new world |
| K | clouds |
| Esc | free the mouse |

Removed: T (panel), J (horizon dial toggle), Z (now G), launch offset, arrows-walk.

Tap vs hold on arrows: a tap nudges a fine step (0.5° nose, 1° hyzer, 0.5 m/s, a few rad/s spin); holding ramps up.
