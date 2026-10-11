extends SceneTree
## TEMPORARY probe: which putts actually go in? Used to find the makeable
## window before settling the chain knobs. Delete once tuning is done.
##
##   godot --headless --path . --script res://tools/putt_probe.gd -- --block-size=1

var _main: Node
var _f := 0
var _started := false

const CASES := [
	[5.0, 9.0, -6.0], [5.0, 10.0, -6.0], [5.0, 11.0, -8.0],
	[6.0, 10.0, -6.0], [6.0, 10.0, -12.0], [6.0, 11.0, -6.0],
	[8.0, 11.0, -6.0], [8.0, 12.0, -8.0],
]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if _f > 5 and not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("PUTT probe starting")
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var b = t.basket
	var player: CharacterBody3D = _main.get_node("Player")
	th.max_discs = 400
	for case: Array in CASES:
		var made := 0
		var arrive := 0.0
		var closest := 0.0
		var height := 0.0
		for trial in 4:
			var r: Dictionary = await _putt(t, th, b, player, case[0], case[1], case[2])
			made += 1 if r.made else 0
			arrive += r.speed
			closest += r.r
			height += r.y
		print("PUTT dist=%4.1f speed=%4.1f loft=%4.1f  made %d/4  closest %.2f m off axis at y=%+.2f, %.1f m/s" % [
			case[0], case[1], case[2], made, closest / 4.0, height / 4.0, arrive / 4.0])
	print("PUTT PROBE DONE")
	quit(0)


func _putt(t, th, b, player, dist: float, speed: float, pitch: float) -> Dictionary:
	var tee: Vector3 = t.spawn_point()
	b.release()
	_main.hole.start(tee, tee + Vector3(0, 0, -dist))
	var c: Vector3 = b.global_position
	player.global_position = tee
	var to := (c - tee) * Vector3(1, 0, 1)
	player.rotation.y = atan2(-to.x, -to.z)
	await process_frame
	var p: Dictionary = th.setup.params()
	p.speed = speed
	p.pitch = pitch
	p.roll = 0.0
	p.spin = 5.2 * speed
	var d = th.throw_disc(p)
	var near := 0.0
	var best_r := 1e9
	var y_at_best := 0.0
	for i in 90:
		await process_frame
		if not is_instance_valid(d):
			break
		var r: float = Vector2(d.global_position.x - c.x, d.global_position.z - c.z).length()
		if r < best_r:
			best_r = r
			y_at_best = d.global_position.y - c.y
			near = d.linear_velocity.length()
		if b.holed != null:
			# Clear it out, or the next trial's release() drops it back
			# through the chains and scores a free make.
			b.release()
			d.queue_free()
			return {"made": true, "speed": near, "r": best_r, "y": y_at_best}
		if d.resting:
			break
	if is_instance_valid(d):
		d.queue_free()
	return {"made": false, "speed": near, "r": best_r, "y": y_at_best}
