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
##   Tab / Shift+Tab  next / previous disc
##
## A tap nudges one fine step; holding repeats, faster the longer you hold.

const DiscModel := preload("res://scripts/disc_model.gd")

signal changed

# name: [min, max, step]
const RANGES := {
	"speed": [5.0, 35.0, 0.5],      # m/s
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
var speed := 24.0
var nose := 0.0
var roll := 0.0
var spin := 125.0
var spin_locked := true
var hand := 1.0                      ## +1 backhand, -1 forehand (right-handed)

var _held := {}                      ## action -> seconds held
var _carry := {}                     ## action -> fractional steps owed


func _ready() -> void:
	for i in discs.size():
		if discs[i].id == "dd2":         # a distance driver to start
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


## How far the disc's left edge is dropped (deg), as you see it from behind.
## Hyzer drops the side it will fade toward: left for a backhand, right for a
## forehand.
func visual_tilt() -> float:
	return roll * hand


func set_value(name: String, v: float) -> void:
	var r: Array = RANGES[name]
	set(name, clampf(snappedf(v, r[2]), r[0], r[1]))
	_sync_spin()
	changed.emit()


func nudge(name: String, steps: float) -> void:
	set_value(name, float(get(name)) + steps * float(RANGES[name][2]))


func _sync_spin() -> void:
	if spin_locked:
		spin = DiscModel.auto_spin(speed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_disc"):
		next_disc(-1 if event is InputEventKey and event.shift_pressed else 1)
	elif event.is_action_pressed("spin_lock"):
		toggle_spin_lock()
	elif event.is_action_pressed("reset_flat"):
		reset_flat()
	elif event.is_action_pressed("hand"):
		toggle_hand()
	else:
		return
	get_viewport().set_input_as_handled()


## Arrows are polled so a hold repeats (and Shift can change mid-hold).
func _process(delta: float) -> void:
	var shift := Input.is_key_pressed(KEY_SHIFT)
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
		if steps > 0.0:
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
