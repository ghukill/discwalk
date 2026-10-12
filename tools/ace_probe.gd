extends SceneTree
## TEMPORARY: can you ace a hole? Throws real shots at a basket set at a range
## of distances and counts how many go in, plus how fast and how high the disc
## was when it got there.
##
##   godot --headless --path . --script res://tools/ace_probe.gd -- --block-size=1
##
## Each case names a disc, a power and a hyzer angle, because with seven discs
## "can you ace it" is no longer one question: a 44 m hole is a putter shot and
## a 90 m hole is a driver shot, and throwing the driver at the putter's hole
## just measures a disc landing long. The shapes come from docs/DISCS.md.
##
## Hyzer is POSITIVE (throw_hud.gd prints r > 0 as hyzer). The understable
## discs need it: thrown flat or anhyzer they turn over and dive, which is a
## short, crooked flight, not an ace attempt.

var _main: Node
var _f := 0
var _started := false

## [distance (m), disc, release speed (m/s), launch pitch (deg), hyzer (deg)]
const CASES := [
	[44.0, "kettle", 18.0, 12.0, 8.0],
	[44.0, "kettle", 18.0, 11.0, 8.0],
	[60.0, "drumlin", 21.0, 10.0, 8.0],
	[90.0, "moraine", 24.0, 12.0, 10.0],
]
const TRIALS := 6
## Long enough for the whole flight plus the ground play. A drive is airborne
## for nearly 7 s under this model; stopping sooner measures the budget, not
## the shot, and does it convincingly (every case misses by the same amount).
const FLIGHT_FRAMES := 1800


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
		var disc = _model(th, case[1])
		if disc == null:
			print("ACE %s: no such disc -- skipped" % case[1])
			continue
		# A thrown disc turns and fades, so aiming straight at the pin misses
		# by metres. Find the aim offset that actually brings it to the basket
		# -- that is what a player does, and it is the only fair test of
		# whether an ace is reachable.
		var aim := await _best_aim(t, th, b, player, case, disc)
		var aces := 0
		var speed_sum := 0.0
		var y_sum := 0.0
		var seen := 0
		var win_r_sum := 0.0
		var win_sp_sum := 0.0
		var win_y_sum := 0.0
		var win_seen := 0
		for i in TRIALS:
			var r: Dictionary = await _drive(t, th, b, player, case, disc, aim.off)
			aces += 1 if r.made else 0
			if r.seen:
				speed_sum += r.speed
				y_sum += r.y
				seen += 1
			if r.win_r < 1e8:
				win_r_sum += r.win_r
				win_sp_sum += r.win_speed
				win_y_sum += r.win_y
				win_seen += 1
		var detail := "closest %.1f m, never near the pole" % aim.r
		if seen > 0:
			detail = "arrived ~%.1f m/s at y=%+.2f (%d/%d on line)" % [
				speed_sum / seen, y_sum / seen, seen, TRIALS]
		# How close it came to an actual catch: lateral miss, speed and height
		# at the best moment the disc was inside the chain window.
		if win_seen > 0:
			detail += "  |  in window: %.2f m off the pole at %.1f m/s, y=%+.2f" % [
				win_r_sum / win_seen, win_sp_sum / win_seen, win_y_sum / win_seen]
		else:
			detail += "  |  never crossed the chain window (%.2f-%.2f m)" % [
				b.CHAIN_BOTTOM, b.BAND_Y]
		print("ACE %3.0f m %-8s speed %2.0f pitch %+.0f hyzer %+.0f (aim %+.0f deg): %d/%d in  --  %s" % [
			case[0], case[1], case[2], case[3], case[4], rad_to_deg(aim.off),
			aces, TRIALS, detail])
	print("ACE DONE")
	quit(0)


func _model(th, id: String):
	for m in th.disc_models:
		if m.id == id:
			return m
	return null


## Find the aim that gets the disc closest to the pole while it is INSIDE the
## chain window, in two stages: a coarse sweep to find the right neighbourhood,
## then a fine one inside it.
##
## Two stages because one coarse sweep cannot do this. The target is a 0.30 m
## catch radius; 3 deg of aim at 44 m moves the disc 2.3 m sideways, so a 3 deg
## sweep steps straight over the basket and reports a near miss no matter how
## good the shot is. The fine step is therefore set as a LATERAL resolution in
## metres and converted to an angle per hole, because a fixed angle fine enough
## at 44 m is twice as coarse as it needs to be at 90 m.
##
## Judged on the in-window distance, falling back to plain closest approach for
## shots that never got there at all. Judging on closest approach alone picks
## the aim that rolls the disc neatly into the base of the pole, which is not
## an ace and says nothing about the chains.
const COARSE_STEP := 3.0             ## deg
const COARSE_SPAN := 24.0            ## deg either side
const FINE_ARC := 0.12               ## m of lateral travel per fine step


func _best_aim(t, th, b, player, case: Array, disc) -> Dictionary:
	var best := await _sweep(t, th, b, player, case, disc,
		-COARSE_SPAN, COARSE_SPAN, COARSE_STEP, {"off": 0.0, "r": 1e9, "win": 1e9})
	# Fine sweep across one coarse step either side of the winner.
	var c0: float = rad_to_deg(best.off)
	var fine := rad_to_deg(FINE_ARC / maxf(float(case[0]), 1.0))
	return await _sweep(t, th, b, player, case, disc,
		c0 - COARSE_STEP, c0 + COARSE_STEP, fine, best)


func _sweep(t, th, b, player, case: Array, disc, from_deg: float, to_deg: float,
		step_deg: float, best: Dictionary) -> Dictionary:
	var n := int(round((to_deg - from_deg) / step_deg)) + 1
	for i in n:
		var off := deg_to_rad(from_deg + i * step_deg)
		var r: Dictionary = await _drive(t, th, b, player, case, disc, off)
		if r.made:
			return {"off": off, "r": 0.0, "win": 0.0}
		var better: bool = r.win_r < best.win if r.win_r < 1e8 or best.win < 1e8 \
			else r.closest < best.r
		if better:
			best = {"off": off, "r": r.closest, "win": r.win_r}
	return best


func _drive(t, th, b, player, case: Array, disc, aim_off := 0.0) -> Dictionary:
	var dist: float = case[0]
	var tee: Vector3 = t.spawn_point()
	b.release()
	_main.hole.start(tee, tee + Vector3(0, 0, -dist))
	var c: Vector3 = b.global_position
	player.global_position = tee
	var to := (c - tee) * Vector3(1, 0, 1)
	player.rotation.y = atan2(-to.x, -to.z) + aim_off
	await process_frame
	var p: Dictionary = th.setup.params()
	p.disc = disc
	p.speed = case[2]
	p.pitch = case[3]
	p.roll = case[4]
	p.spin = 5.2 * float(case[2])
	var d = th.throw_disc(p)
	var best_r := 1e9                   ## Closest horizontal approach, any height.
	var sp := 0.0
	var y := 0.0
	# The same, but only while the disc is between the bottom of the chains and
	# the band -- the band of heights where a catch is even possible. This is
	# the number that says how close the shot came to going in; the one above
	# is usually taken at ground level, next to the pole, long after the disc
	# stopped being an ace.
	var win_r := 1e9
	var win_sp := 0.0
	var win_at := 0.0
	for i in FLIGHT_FRAMES:
		await process_frame
		if not is_instance_valid(d):
			break
		var rel: Vector3 = d.global_position - c
		var r: float = Vector2(rel.x, rel.z).length()
		if r < best_r:
			best_r = r
			sp = d.linear_velocity.length()
			y = rel.y
		if rel.y >= b.CHAIN_BOTTOM and rel.y <= b.BAND_Y and r < win_r:
			win_r = r
			win_sp = d.linear_velocity.length()
			win_at = rel.y
		if b.holed != null:
			b.release()
			d.queue_free()
			return {"made": true, "seen": true, "speed": sp, "y": y, "closest": 0.0,
				"win_r": 0.0, "win_speed": win_sp, "win_y": win_at}
		if d.resting:
			break
	if is_instance_valid(d):
		d.queue_free()
	return {"made": false, "seen": best_r < 1.5, "speed": sp, "y": y, "closest": best_r,
		"win_r": win_r, "win_speed": win_sp, "win_y": win_at}
