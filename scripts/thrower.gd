extends Node
## Throwing discs (step 1: a block out of a cannon).
##
##   1-9, 0   throw at power 1..10 along where you're looking (0 = 10)
##   click    throw again at the last power
##   F        fetch: walk (well, teleport) to your last disc
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

var power := 5
var discs: Array = []
var _last: Node = null
var _flying_text := ""
var _result_text := ""


func _ready() -> void:
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	for level in range(1, 11):
		if event.is_action_pressed("throw_%d" % level):
			power = level
			throw(level)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("fetch"):
		fetch()
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
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)   # don't bonk yourself
	var vel := fwd * level * speed_per_level + player.velocity
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
	disc.launch(origin, vel, spin)
	disc.came_to_rest.connect(_on_rest)
	disc.tree_exited.connect(func() -> void: discs.erase(disc))
	discs.append(disc)
	_last = disc
	while discs.size() > max_discs:
		var old: Node = discs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_result_text = ""
	return disc


## Teleports the walker next to the last disc, facing the same way.
func fetch() -> void:
	if not is_instance_valid(_last):
		return
	var p: Vector3 = _last.global_position
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
	_update_label()


func _process(_delta: float) -> void:
	if is_instance_valid(_last) and not _last.resting:
		_flying_text = "in flight: %.1f m" % _last.distance()
	else:
		_flying_text = ""
	_update_label()


func _on_rest(disc: Node) -> void:
	if disc != _last:
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
	var lines := ["throw: 1-9, 0 = power 1-10  ·  click = power %d  ·  F fetch" % power]
	if _flying_text != "":
		lines.append(_flying_text)
	elif _result_text != "":
		lines.append(_result_text)
	label.text = "\n".join(lines)
