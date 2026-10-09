extends Node
## Throwing discs (step 1: a block out of a cannon).
##
##   1-9, 0   set power 1..10 (0 = 10)
##   click/T  throw at the current power, along where you're looking
##   F        fetch: teleport to your last disc. If it's still flying, you
##            take over its speed and direction and fly on with it.
##   B        toggle the beams of light over resting discs
##   C        collect: every disc rolls home to you, building up speed
##
## Power p launches at p x speed_per_level m/s (default 4 m/s per level, so
## 0 = 40 m/s, about a strong disc golf drive). Aim is your view direction.

const DISC_SCRIPT := preload("res://scripts/disc.gd")

@export var speed_per_level := 4.0
@export var max_discs := 12          ## Older discs are cleared away.

var terrain: Node3D
var player: CharacterBody3D
var camera: Camera3D
var label: Label
var status_label: Label                  ## Upper-right: power + beams.

var power := 5
var beams := true
var discs: Array = []
var _last: Node = null
var _flying_text := ""
var _result_text := ""
var _collected := 0


func _ready() -> void:
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	for level in range(1, 11):
		if event.is_action_pressed("throw_%d" % level):
			power = level
			_update_label()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("fetch"):
		fetch()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("throw"):
		throw(power)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("collect"):
		collect()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("beams"):
		set_beams(not beams)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		throw(power)
		get_viewport().set_input_as_handled()


## Launches a disc from just in front of the camera.
func throw(level: int) -> Node:
	var fwd := -camera.global_transform.basis.z
	var origin := camera.global_position + fwd * 0.5
	var disc: RigidBody3D = RigidBody3D.new()
	disc.set_script(DISC_SCRIPT)
	disc.name = "Disc"
	disc.terrain = terrain
	disc.power = level
	disc.beam_on = beams
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)   # don't bonk yourself
	var vel := fwd * level * speed_per_level + player.velocity
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
	disc.launch(origin, vel, spin)
	disc.came_to_rest.connect(_on_rest)
	disc.tree_exited.connect(func() -> void: discs.erase(disc))
	discs.append(disc)
	_last = disc
	_collected = 0
	while discs.size() > max_discs:
		var old: Node = discs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_result_text = ""
	return disc


## Sends every disc rolling home to the player.
func collect() -> void:
	var n := 0
	for d in discs:
		if is_instance_valid(d) and not d.collecting:
			d.start_collect(player)
			if not d.collected.is_connected(_on_collected):
				d.collected.connect(_on_collected)
			n += 1
	if n > 0:
		_collected = 0
		_result_text = ""


func _on_collected(_disc: Node) -> void:
	_collected += 1
	_result_text = "collected %d disc%s" % [_collected, "" if _collected == 1 else "s"]


## Turns every disc's beam of light on or off (and future ones too).
func set_beams(on: bool) -> void:
	beams = on
	for d in discs:
		if is_instance_valid(d):
			d.set_beam(on)
	_update_label()


## Teleports the walker to the last disc. A resting disc: stand beside it,
## facing the same way. A flying disc: your eyes go where it is and you
## inherit its velocity, so you fly on alongside it until you land.
func fetch() -> void:
	if not is_instance_valid(_last):
		return
	var p: Vector3 = _last.global_position
	if not _last.resting:
		var at := p - Vector3(0, 1.6, 0)                     # eyes at the disc
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + 0.1)
		player.fling(at, _last.linear_velocity)
		return
	var back := Vector3(camera.global_transform.basis.z.x, 0, camera.global_transform.basis.z.z)
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var at := p + back * 1.2
	at.y = maxf(terrain.height_at(at.x, at.z), p.y) + 0.2
	player.respawn(at)


func clear() -> void:
	for d in discs:
		if is_instance_valid(d):
			d.queue_free()
	discs.clear()
	_last = null
	_result_text = ""
	_collected = 0
	_update_label()


func _process(_delta: float) -> void:
	var rolling := 0
	for d in discs:
		if is_instance_valid(d) and d.collecting:
			rolling += 1
	if rolling > 0:
		_flying_text = "collecting: %d rolling home…%s" % [rolling,
			("  (%d in)" % _collected) if _collected > 0 else ""]
	elif is_instance_valid(_last) and not _last.resting:
		_flying_text = "in flight: %.1f m" % _last.distance()
	else:
		_flying_text = ""
	_update_label()


func _on_rest(disc: Node) -> void:
	if disc != _last or _collected > 0:
		return
	var notes := []
	if disc.bark_hits > 0:
		notes.append("hit bark x%d" % disc.bark_hits)
	if disc.leaf_cells > 0:
		notes.append("through leaves")
	if disc.splashed:
		notes.append("splash!")
	_result_text = "last throw: %.1f m at power %d (peak %.1f m)%s" % [
		disc.distance(), disc.power, disc.max_height,
		("  ·  " + ", ".join(notes)) if notes.size() > 0 else ""]


func _update_label() -> void:
	if label == null:
		return
	if status_label != null:
		status_label.text = "Velocity: %d  (%d m/s)\nBeams: %s" % [
			power, int(power * speed_per_level), "on" if beams else "off"]
	var lines := ["1-9, 0 set power  ·  click or T throw  ·  F fetch  ·  C collect  ·  B beams"]
	if _flying_text != "":
		lines.append(_flying_text)
	elif _result_text != "":
		lines.append(_result_text)
	label.text = "\n".join(lines)
