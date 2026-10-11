extends SceneTree
## TEMPORARY: can you ace a hole? Throws drives at a basket set at a range
## of distances and counts how many go in, plus how fast and how high the
## disc was when it got there.
##
##   godot --headless --path . --script res://tools/ace_probe.gd -- --block-size=1

var _main: Node
var _f := 0
var _started := false

## [distance (m), launch pitch (deg)] -- low pitches keep the disc under the
## 1.32 m band instead of sailing over it at apex.
## [distance (m), launch pitch (deg), release speed (m/s)]. Power matched to
## the hole: a full-power drive at a 30 m basket lands short and skids in at
## ground level, which is not what an ace looks like.
const CASES := [
	[40.0, 3.0, 24.0], [40.0, 4.0, 24.0], [40.0, 5.0, 24.0],
	[44.0, 4.0, 24.0], [44.0, 5.0, 24.0], [44.0, 6.0, 24.0],
	[50.0, 5.0, 24.0], [50.0, 6.0, 24.0],
]
const TRIALS := 6


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
	var b = t.basket
	var player: CharacterBody3D = _main.get_node("Player")
	th.max_discs = 400
	print("ACE chain_max_force=%.0f" % b.chain_max_force)
	for case: Array in CASES:
		var dist: float = case[0]
		var pitch: float = case[1]
		var sp0: float = case[2]
		# A thrown disc fades, so aiming straight at the pin misses by
		# metres. Find the aim offset that actually brings it to the basket
		# -- that is what a player does, and it is the only fair test of
		# whether an ace is reachable.
		var aim := await _best_aim(t, th, b, player, dist, pitch, sp0)
		var aces := 0
		var speed_sum := 0.0
		var y_sum := 0.0
		var seen := 0
		for i in TRIALS:
			var r: Dictionary = await _drive(t, th, b, player, dist, aim.off, pitch, sp0)
			aces += 1 if r.made else 0
			if r.seen:
				speed_sum += r.speed
				y_sum += r.y
				seen += 1
		var detail := "closest %.1f m, never near the pole" % aim.r
		if seen > 0:
			detail = "arrived ~%.1f m/s at y=%+.2f (%d/%d on line)" % [
				speed_sum / seen, y_sum / seen, seen, TRIALS]
		print("ACE %3.0f m pitch %+.0f speed %.0f (aim %+.0f deg): %d/%d in  --  %s" % [
			dist, pitch, sp0, rad_to_deg(aim.off), aces, TRIALS, detail])
	print("ACE DONE")
	quit(0)


## Sweep aim offsets and keep the one that passes closest to the pole.
func _best_aim(t, th, b, player, dist: float, pitch: float, sp0: float) -> Dictionary:
	var best := {"off": 0.0, "r": 1e9}
	for step in 17:
		var off := deg_to_rad(-24.0 + step * 3.0)
		var r: Dictionary = await _drive(t, th, b, player, dist, off, pitch, sp0)
		if r.closest < best.r:
			best = {"off": off, "r": r.closest}
	return best


func _drive(t, th, b, player, dist: float, aim_off := 0.0, pitch := 15.0, sp0 := 24.0) -> Dictionary:
	var tee: Vector3 = t.spawn_point()
	b.release()
	_main.hole.start(tee, tee + Vector3(0, 0, -dist))
	var c: Vector3 = b.global_position
	player.global_position = tee
	var to := (c - tee) * Vector3(1, 0, 1)
	player.rotation.y = atan2(-to.x, -to.z) + aim_off
	await process_frame
	var p: Dictionary = th.setup.params()
	p.speed = sp0
	p.pitch = pitch
	p.roll = -8.0                       # a little hyzer, so it comes down on line
	p.spin = 5.2 * sp0
	var d = th.throw_disc(p)
	var best_r := 1e9
	var sp := 0.0
	var y := 0.0
	for i in 400:
		await process_frame
		if not is_instance_valid(d):
			break
		var rel: Vector3 = d.global_position - c
		var r: float = Vector2(rel.x, rel.z).length()
		if r < best_r:
			best_r = r
			sp = d.linear_velocity.length()
			y = rel.y
		if b.holed != null:
			b.release()
			d.queue_free()
			return {"made": true, "seen": true, "speed": sp, "y": y, "closest": 0.0}
		if d.resting:
			break
	if is_instance_valid(d):
		d.queue_free()
	return {"made": false, "seen": best_r < 1.5, "speed": sp, "y": y, "closest": best_r}
