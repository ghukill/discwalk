extends SceneTree
## Headless landing stress test: 48 real discs thrown from spawn all round
## the compass (every disc, mixed speeds, angles, hyzer/anhyzer). Fails if
## any ends up under the terrain or falls out of the world. (Before Jolt,
## ~40% of thin discs tunnelled through the heightmap on landing.)
##
##   godot --headless --path . --script res://tools/landing_test.gd [-- --block-size=0.5]

var _main: Node
var _f := 0
var _discs: Array = []
var _bad := {}
var _last_seen := {}


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _collision_height(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 200.0, at.z), Vector3(at.x, -50.0, at.z))
	q.exclude = _discs.filter(func(x) -> bool: return is_instance_valid(x)).map(func(x) -> RID: return x.get_rid())
	q.exclude.append(_main.get_node("Player").get_rid())
	var r := space.intersect_ray(q)
	return r.position.y if not r.is_empty() else -1e9


func _process(_d: float) -> bool:
	_f += 1
	var th = _main.thrower
	th.max_discs = 1000
	if _f >= 10 and _f < 10 + 48 * 3 and (_f - 10) % 3 == 0:
		var k := (_f - 10) / 3
		_main.get_node("Player").rotation.y = TAU * k / 48.0
		var p: Dictionary = th.panel.params()
		p.disc = th.disc_models[k % th.disc_models.size()]
		p.speed = 14.0 + (k % 5) * 3.0
		p.pitch = 6.0 + (k % 3) * 5.0
		p.roll = -20.0 + (k % 7) * 7.0
		p.spin = 5.2 * p.speed
		_discs.append(th.throw_disc(p))
	for i in _discs.size():
		var d = _discs[i]
		if not is_instance_valid(d):
			if not _bad.has(i):
				_bad[i] = "lost (last seen %s)" % _last_seen.get(i, "?")
			continue
		_last_seen[i] = "%s v=%s flying=%s landed_by=%s ground=%.2f" % [d.global_position, d.linear_velocity, d.flying, d.landed_by, _collision_height(d.global_position)]
		# Compare with the COLLISION surface (smooth heightmap through the block
		# centres), not the block tops: on a slope the two differ by up to a
		# block. A disc is "under" if it's a disc-width below what a ray from
		# the sky hits first (ignoring discs).
		var gy := _collision_height(d.global_position)
		# (A frame or two below before the rescue in disc.gd kicks in is fine;
		# ending up there, or lost, is not.)
		if _f > 60 * 24 and d.global_position.y < gy - 0.25 and not d.splashed:
			if not _bad.has(i):
				_bad[i] = "under at frame %d: %s" % [_f, _last_seen[i]]
	if _f > 60 * 25:
		# Where did the "under" ones end up?
		for i in _bad:
			var d = _discs[i]
			if is_instance_valid(d):
				_bad[i] += "  -> END %s ground=%.2f resting=%s" % [d.global_position, _collision_height(d.global_position), d.resting]
		var rescued := 0
		for d in _discs:
			if is_instance_valid(d):
				rescued += d.rescues
		var gp := []
		for d in _discs:
			if is_instance_valid(d) and d.landed_by == "ground":
				gp.append(d.distance() - d.flight_dist)
		gp.sort()
		if not gp.is_empty():
			print("LANDING ground play after landing on the ground (%d discs): median %.1f m, max %.1f m" % [gp.size(), gp[gp.size() / 2], gp[gp.size() - 1]])
		print("LANDING rescued (popped back above ground): %d" % rescued)
		var ok := _bad.is_empty()
		print("LANDING %d discs, %d under the ground or lost %s" % [_discs.size(), _bad.size(), _bad])
		print("LANDING " + ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
		return true
	return false
