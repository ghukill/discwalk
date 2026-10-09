extends SceneTree
## Headless collect check: scatters discs around spawn, waits for them to
## land, presses "collect", and reports how many roll home, how long they
## take, and how speed builds up (should start slow, then accelerate).
##
##   godot --headless --path . --script res://tools/collect_test.gd [-- --block-size=0.5]

var _main: Node
var _frames := 0
var _discs: Array = []
var _collect_frame := -1
var _arrivals: Array = []            # seconds after collect
var _speed_log := {}                 # second -> max speed among rolling discs


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var thrower = _main.thrower
	if _frames == 5:
		var t = _main.get_node("Terrain")
		var spawn: Vector3 = t.spawn_point()
		thrower.max_discs = 100
		for k in 8:
			var a := TAU * k / 8.0
			var d = thrower.throw(3)
			d.launch(spawn + Vector3(0, 0.6, 0), Vector3(cos(a) * 9.0, 5.0, sin(a) * 9.0), Vector3.ZERO)
			d.collected.connect(func(_x) -> void: _arrivals.append((_frames - _collect_frame) / 60.0))
			_discs.append(d)
	if _collect_frame < 0 and _frames > 30:
		var all_rest := true
		for d in _discs:
			if is_instance_valid(d) and not d.resting:
				all_rest = false
		if all_rest or _frames > 60 * 15:
			_collect_frame = _frames
			thrower.collect()
	if _collect_frame > 0:
		var sec := int((_frames - _collect_frame) / 60.0)
		for d in _discs:
			if is_instance_valid(d) and d.collecting:
				var sp: float = Vector2(d.linear_velocity.x, d.linear_velocity.z).length()
				_speed_log[sec] = maxf(_speed_log.get(sec, 0.0), sp)
		var left := 0
		for d in _discs:
			if is_instance_valid(d) and d.collecting:
				left += 1
		if left == 0 or _frames - _collect_frame > 60 * 45:
			var stuck := 0
			for d in _discs:
				if is_instance_valid(d):
					stuck += 1
			var speeds := []
			for s in range(0, 6):
				speeds.append("%ds:%.1f" % [s, _speed_log.get(s, 0.0)])
			print("COLLECT home=%d/%d not_home=%d times=%s" % [_arrivals.size(), _discs.size(), stuck, str(_arrivals)])
			print("COLLECT max horizontal speed by second: %s" % " ".join(speeds))
			var ok: bool = _arrivals.size() >= _discs.size() - 2 \
				and _speed_log.get(0, 99.0) < 3.0
			print("COLLECT " + ("PASS" if ok else "FAIL"))
			quit(0 if ok else 1)
			return true
	return false
