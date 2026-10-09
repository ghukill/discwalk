extends SceneTree
## Headless smoke test: loads the main scene, lets physics settle, and checks
## the world generated and the walker is standing on the ground.
##
##   godot --headless --path . --script res://tools/smoke_test.gd

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 180:
		return false

	var terrain = _main.get_node("Terrain")
	var player: CharacterBody3D = _main.get_node("Player")
	var chunks: int = terrain.get_node("Chunks").get_child_count()
	var verts := 0
	for chunk in terrain.get_node("Chunks").get_children():
		verts += chunk.mesh.get_faces().size()
	var water_ys := []
	for lake in terrain.lakes:
		water_ys.append(snappedf(lake.water_y, 0.01))

	print("SMOKE block_size=%.2f" % terrain.block_size)
	print("SMOKE size=%d chunks=%d triangles=%d lakes=%d water_y=%s" % [
		terrain.size, chunks, verts / 3, terrain.lakes.size(), str(water_ys)])
	var flora = terrain.flora
	var kinds := {}
	for tr in flora.trees:
		kinds[tr.kind] = kinds.get(tr.kind, 0) + 1
	print("SMOKE oaks=%d %s voxels=%d flowers=%s" % [
		flora.trees.size(), str(kinds), flora.voxel_count, str(flora.flower_counts)])
	print("SMOKE player=%s on_floor=%s" % [player.global_position, player.is_on_floor()])

	var ok: bool = chunks == terrain.size_chunks * terrain.size_chunks \
		and terrain.lakes.size() > 0 and player.is_on_floor() \
		and flora.trees.size() > 10 and flora.flower_counts.size() >= 5
	print("SMOKE " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
	return true
