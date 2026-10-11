extends SceneTree
## TEMPORARY: how fast, and how high, is a disc when it gets downrange?
##
## Answers the question "can you ace a hole?" -- an ace needs the disc to
## arrive inside the chain window (0.75-1.30 m up) at a speed the chains can
## absorb. Prints speed and height as the disc crosses each distance mark.
##
##   godot --headless --path . --script res://tools/arrival_probe.gd -- --block-size=1

var _main: Node
var _f := 0
var _started := false

const MARKS := [20.0, 40.0, 60.0, 80.0, 100.0, 120.0]
## [release speed (m/s), pitch (deg), hyzer (deg), disc id]
const THROWS := [
	[24.0, 12.0, 0.0, "moraine"],
	[24.0, 16.0, -8.0, "moraine"],
	[20.0, 14.0, 0.0, "erratic"],
	[18.0, 12.0, 0.0, "till"],
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
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	th.max_discs = 400
	# No basket in the way, and flat open ground matters less than clear air.
	if t.basket != null:
		t.basket.place(t.spawn_point() + Vector3(0, 0, 400.0))
	print("DIST  (speed m/s / height above launch m) at each mark")
	for spec: Array in THROWS:
		await _throw(t, th, player, spec)
	print("DIST DONE")
	quit(0)


func _throw(t, th, player, spec: Array) -> void:
	var tee: Vector3 = t.spawn_point()
	player.global_position = tee
	player.rotation.y = 0.0
	await process_frame
	var p: Dictionary = th.setup.params()
	p.speed = spec[0]
	p.pitch = spec[1]
	p.roll = spec[2]
	p.spin = 5.2 * spec[0]
	var found := false
	for m in th.disc_models:
		if m.id == spec[3]:
			p.disc = m
			found = true
	# Loud, not silent: an id that no longer exists would otherwise quietly
	# run the default disc and look like a real measurement.
	if not found:
		print("DIST %s: no such disc -- skipped" % spec[3])
		return
	var d = th.throw_disc(p)
	var launch_y: float = d.global_position.y
	var next := 0
	var out := []
	for i in 600:
		await process_frame
		if not is_instance_valid(d):
			break
		var run: float = d.distance()
		while next < MARKS.size() and run >= MARKS[next]:
			out.append("%3.0fm: %4.1f / %+4.1f" % [
				MARKS[next], d.linear_velocity.length(), d.global_position.y - launch_y])
			next += 1
		if d.resting or next >= MARKS.size():
			break
	var carried: float = d.distance() if is_instance_valid(d) else 0.0
	print("DIST %s sp=%.0f pitch=%+.0f hyzer=%+.0f  carry %.0f m  |  %s" % [
		spec[3], spec[0], spec[1], spec[2], carried, "   ".join(out)])
	if is_instance_valid(d):
		d.queue_free()
