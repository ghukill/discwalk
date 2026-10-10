extends SceneTree
## Ground play on flat grass: 48 throws (4 discs x 2 speeds x 2 angles x
## hyzer/flat/anhyzer) over an empty floor; reports how far discs travel
## after first contact (rest - carry). Use it to tune `landed_friction` in
## flying_disc.gd. Passes if they all rest and ground play averages 10-25 m.
##
##   godot --headless --path . --script res://tools/skip_test.gd
const FD := preload("res://scripts/flying_disc.gd")
const DM := preload("res://scripts/disc_model.gd")
var cases := []; var f := 0
func _initialize():
	var fl := StaticBody3D.new(); var cs := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(16000, 1, 2000); cs.shape = b; cs.position = Vector3(7000, -0.5, 0); fl.add_child(cs); root.add_child(fl)
	var s := GDScript.new(); s.source_code = "extends Node3D\nvar block_size := 1.0\nvar lakes: Array = []\nvar flora := F.new()\nfunc height_at(_x: float, _z: float) -> float:\n\treturn 0.0\nclass F:\n\tfunc voxel_at(_c: Vector3i) -> int:\n\t\treturn 0\n"; s.reload()
	var stub := Node3D.new(); stub.set_script(s); root.add_child(stub)
	var models := {}
	for m in DM.load_all(): models[m.id] = m
	var i := 0
	for id in ["dd2", "fd2", "cd1", "cd5"]:
		for sp in [16.0, 22.0]:
			for pitch in [4.0, 10.0]:
				for roll in [-15.0, 0.0, 20.0]:
					var d: RigidBody3D = RigidBody3D.new(); d.set_script(FD); d.terrain = stub; d.model = models[id]; root.add_child(d)
					d.collision_layer = 2; d.collision_mask = 1
					var ls = DM.launch_state(Vector3.FORWARD, sp, pitch, 0.0, roll, 1.0)
					d.launch_disc(Vector3(i * 150.0, 1.3, 0), ls[0], ls[1], 5.2 * sp, 1.0)
					cases.append(d); i += 1
func _process(_d):
	f += 1
	if f > 60 * 30 or (f > 30 and cases.all(func(d): return not is_instance_valid(d) or d.resting)):
		var rolls := []
		var total := 0.0
		for d in cases:
			if not is_instance_valid(d): continue
			var r: float = d.distance() - d.flight_dist
			rolls.append(r); total += r
		rolls.sort()
		print("SKIP n=%d mean=%.1f m  median=%.1f  min=%.1f max=%.1f  (rested %d)" % [rolls.size(), total / rolls.size(), rolls[rolls.size() / 2], rolls[0], rolls[rolls.size() - 1], cases.filter(func(d): return is_instance_valid(d) and d.resting).size()])
		var mean := total / rolls.size()
		var ok := rolls.size() == cases.size() and mean > 10.0 and mean < 25.0
		print("SKIP " + ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1); return true
	return false
