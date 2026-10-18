extends Node
## The throw you have set up: disc, release speed, nose, hyzer/anhyzer, spin,
## backhand/forehand. Replaces the old T panel. Everything is set from the
## keyboard (the mouse only ever looks), and it all carries over from throw
## to throw so you can repeat and fine-tune a shot.
##
##   ↑ / ↓            nose up / down
##   ← / →            tilt the disc that way (drops that edge). For a backhand
##                    left = hyzer; for a forehand left = anhyzer
##   Shift + ↑ / ↓    release speed (discs AND cubes)
##   Shift + ← / →    spin, only when unlocked
##   X                spin lock / unlock (locked = auto spin from speed)
##   R                reset to flat (nose 0, hyzer 0)
##   H                backhand <-> forehand
##   I                speed readout in mph <-> m/s
##   Q / E            previous / next disc
##
## A tap nudges one fine step; holding repeats, faster the longer you hold.
## Controller: the D-pad is the arrows, RB is Shift. LB tapped is H; LB held
## turns the D-pad into the disc page: ← / → previous / next disc, ↑ reset
## to flat (R), ↓ spin lock (X), one per press. Any other button pressed
## during the hold (LB + X = collect, say) cancels the hand flip. Both
## bumpers held: the D-pad does nothing.

const DiscModel := preload("res://scripts/disc_model.gd")

signal changed

## Release speed is stored in m/s, because the flight model is, but the player
## sets it in mph: a disc golfer thinks in mph, and 0-80 is the human range (an
## 80 mph release is a big arm; the old 35 m/s cap was 78 mph by accident).
## The range and the step below are therefore whole mph converted to m/s, so
## set_value()'s snap always lands on an exact mph and the readout never shows
## a number the arrows cannot reach.
const MPH_PER_MS := 2.2369363        ## mph per m/s.
const SPEED_MAX_MPH := 80.0
const SPEED_STEP_MPH := 1.0
const SPEED_STEP_MS := 0.5           ## The step when the readout is in m/s.

# name: [min, max, step]
const RANGES := {
	"speed": [0.0, SPEED_MAX_MPH / MPH_PER_MS, SPEED_STEP_MPH / MPH_PER_MS],   # m/s, set in mph
	"nose": [-10.0, 10.0, 0.5],     # deg, + = nose up
	"roll": [-40.0, 40.0, 1.0],     # deg, + = hyzer, - = anhyzer
	"spin": [20.0, 200.0, 2.0],     # rad/s
}
const REPEAT_DELAY := 0.3            ## Hold this long before repeating (s).
const REPEAT_RATE := 10.0            ## Steps per second once repeating...
const REPEAT_RAMP := 30.0            ## ... plus this much per second held,
const REPEAT_MAX := 45.0             ## ... up to this.

var discs: Array = []                ## DiscModel list
var disc_index := 0
## 24 m/s, which reads as 54 mph. Deliberately NOT an exact whole mph: every
## tool and test that throws with params() inherits this, and nudging it even
## 0.15 m/s moves a long throw far enough to change where it lands (it put
## course_test's shot in a lake). The display rounds to 54 and the first arrow
## press snaps to exactly 55 or 53, so it still steps by 1 mph on screen.
var speed := 24.0
var nose := 0.0
var roll := 0.0
var spin := 125.0
var spin_locked := true
## Show release speed in mph (the default) or m/s. Display only: the throw and
## the flight are in m/s either way. It also picks the arrow step, so whichever
## unit you are reading moves in round numbers rather than 0.447 at a time.
var mph := true
var hand := 1.0                      ## +1 backhand, -1 forehand (right-handed)

var _held := {}                      ## action -> seconds held
var _carry := {}                     ## action -> fractional steps owed
var _lb_used := false                ## Something else pressed during this LB hold: no hand flip.


func _ready() -> void:
	for i in discs.size():
		if discs[i].id == "moraine":     # the distance driver to start
			disc_index = i
	_sync_spin()


func disc():
	return discs[disc_index] if not discs.is_empty() else null


## {disc, speed, nose, roll, spin, hand}: what throw_disc() wants.
func params() -> Dictionary:
	_sync_spin()
	return {"disc": disc(), "speed": speed, "nose": nose, "roll": roll,
		"spin": spin, "hand": hand}


func next_disc(dir := 1) -> void:
	if discs.is_empty():
		return
	disc_index = posmod(disc_index + dir, discs.size())
	changed.emit()


func reset_flat() -> void:
	nose = 0.0
	roll = 0.0
	changed.emit()


func toggle_spin_lock() -> void:
	spin_locked = not spin_locked
	_sync_spin()
	changed.emit()


func toggle_hand() -> void:
	hand = -hand
	changed.emit()


## Release speed as the player sets it (mph).
func speed_mph() -> float:
	return speed * MPH_PER_MS


## Switch the speed readout between mph and m/s.
##
## Display only: the stored speed is left exactly as it is. Re-snapping it onto
## the new unit's grid would make the readout a round number straight away, but
## at the cost of quietly changing the throw you had dialled in (55 mph would
## become 24.5 m/s), and a readout toggle has no business doing that. The next
## arrow press lands on the new grid by itself.
func toggle_units() -> void:
	mph = not mph
	changed.emit()


## `ms` (m/s) in whatever unit the player is reading, and its name. Everything
## that shows a speed goes through these two, so the HUD and the in-flight
## readout can never disagree about what the number means.
func in_units(ms: float) -> float:
	return ms * MPH_PER_MS if mph else ms


func unit_name() -> String:
	return "mph" if mph else "m/s"


## A speed, formatted for display: whole mph, or m/s to one decimal.
func speed_str(ms: float) -> String:
	return ("%.0f" if mph else "%.1f") % in_units(ms)


## How far the disc's left edge is dropped (deg), as you see it from behind.
## Hyzer drops the side it will fade toward: left for a backhand, right for a
## forehand.
func visual_tilt() -> float:
	return roll * hand


## [min, max, step] for a dial, all in the unit it is stored in. Speed is the
## only one that moves: its step follows the unit you are reading it in.
func range_of(name: String) -> Array:
	var r: Array = RANGES[name]
	if name == "speed":
		return [r[0], r[1], SPEED_STEP_MPH / MPH_PER_MS if mph else SPEED_STEP_MS]
	return r


func set_value(name: String, v: float) -> void:
	var r: Array = range_of(name)
	set(name, clampf(snappedf(v, r[2]), r[0], r[1]))
	_sync_spin()
	changed.emit()


func nudge(name: String, steps: float) -> void:
	set_value(name, float(get(name)) + steps * float(range_of(name)[2]))


func _sync_spin() -> void:
	if spin_locked:
		spin = DiscModel.auto_spin(speed)


## Watches every controller button (even ones another node handles, like
## LB + X = collect): any press during an LB hold means it wasn't a tap.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index != JOY_BUTTON_LEFT_SHOULDER \
			and Input.is_action_pressed("setup_disc"):
		_lb_used = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_disc"):
		next_disc(1)
	elif event.is_action_pressed("prev_disc"):
		next_disc(-1)
	elif event.is_action_pressed("spin_lock"):
		toggle_spin_lock()
	elif event.is_action_pressed("reset_flat"):
		reset_flat()
	elif event.is_action_pressed("hand"):
		toggle_hand()
	elif event.is_action_pressed("units"):
		toggle_units()
	elif event.is_action_pressed("setup_disc"):
		_lb_used = false
	elif event.is_action_released("setup_disc"):
		if not _lb_used:
			toggle_hand()
	else:
		return
	get_viewport().set_input_as_handled()


## Arrows are polled so a hold repeats (and Shift can change mid-hold).
func _process(delta: float) -> void:
	var shift := Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("setup_alt")
	var disc_mode := InputMap.has_action("setup_disc") and Input.is_action_pressed("setup_disc")
	for action in ["tilt_up", "tilt_down", "tilt_left", "tilt_right"]:
		if not InputMap.has_action(action) or not Input.is_action_pressed(action):
			_held.erase(action)
			_carry.erase(action)
			continue
		var steps := 0.0
		if not _held.has(action):
			_held[action] = 0.0
			_carry[action] = 0.0
			steps = 1.0
		else:
			_held[action] += delta
			var t: float = _held[action] - REPEAT_DELAY
			if t > 0.0:
				_carry[action] += delta * minf(REPEAT_RATE + REPEAT_RAMP * t, REPEAT_MAX)
				steps = floorf(_carry[action])
				_carry[action] -= steps
		if steps <= 0.0:
			continue
		if disc_mode:
			# LB page: one per fresh press (no repeat, and a D-pad already
			# held when LB went down doesn't count); with RB too, nothing.
			_lb_used = true
			if not shift and _held[action] == 0.0:
				match action:
					"tilt_left", "tilt_right":
						next_disc(-1 if action == "tilt_left" else 1)
					"tilt_up":
						reset_flat()
					"tilt_down":
						toggle_spin_lock()
		else:
			_apply(action, shift, steps)


func _apply(action: String, shift: bool, steps: float) -> void:
	match action:
		"tilt_up":
			nudge("speed" if shift else "nose", steps)
		"tilt_down":
			nudge("speed" if shift else "nose", -steps)
		"tilt_left", "tilt_right":
			var dir := -1.0 if action == "tilt_left" else 1.0
			if shift:
				if not spin_locked:
					nudge("spin", dir * steps)
			else:
				# Left drops the left edge: hyzer for a backhand.
				nudge("roll", -dir * hand * steps)
