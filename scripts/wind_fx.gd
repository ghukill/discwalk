extends Node3D
## What the wind looks like. The wind itself (wind.gd) is only numbers; this
## is everything in the world that lets you read it without the HUD:
##
## - STREAKS: a few dozen pale slivers drifting through the air round you,
##   carried at exactly the speed the wind has at their height. So they are
##   a wind gauge you can look through: slow near the grass, quick overhead,
##   surging when a gust comes, and pointing the way a disc will be pushed.
##   Longer the faster they go. None when it is calm.
## - CLOUDS drift with it (clouds.gd), faster the harder it blows.
## - FLOWERS lean and shake with it (the sway shader on flora.gd's material).
##
## Calm leaves the clouds and flowers on their own gentle defaults, so a
## still day looks the way the game always has.

const COUNT := 96                    ## Streaks alive at once.
const BOX := Vector3(30.0, 11.0, 30.0)   ## They live in a box this big, mostly ahead of the camera (m).
const LOW := 0.6                     ## ... from this far above the ground (m).
const LIFE := Vector2(1.6, 3.4)      ## Seconds a streak lasts.
const THICK := 0.045                 ## Streak cross-section (m).
const STRETCH := 0.13                ## Streak length per m/s of wind (s): a short motion blur.
const COLOR := Color(1.0, 1.0, 1.0)
const ALPHA := 0.5
const NEAR := Vector2(2.5, 7.0)      ## Invisible closer to the camera than x, fully there from y (m).
## The sway shader's own defaults (shaders/sway.gdshader), for calm days, and
## what a gale does to them.
const SWAY_CALM := 0.22
const SWAY_GALE := 0.75
const SWAY_SPEED_CALM := 1.6
const SWAY_SPEED_GALE := 3.4
const SWAY_DIR_CALM := Vector2(0.8, 0.6)

var wind: RefCounted                 ## wind.gd
var terrain: Node3D
var clouds: Node3D
var camera: Camera3D
var streaks_on := true

var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _cloud_calm := Vector2.ZERO      ## The clouds' own drift, kept for calm days.
var _shown := 0.0                    ## 0..1: streaks fade in and out with the wind.


func _ready() -> void:
	top_level = true
	_rng.seed = 7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = COUNT
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Streaks"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The streaks follow the camera, so their box is wherever it is: never cull.
	_mmi.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	add_child(_mmi)
	_pos.resize(COUNT)
	_age.resize(COUNT)
	_life.resize(COUNT)
	for i in COUNT:
		_life[i] = 0.0                   # all due a respawn on the first windy frame
	if clouds != null:
		_cloud_calm = clouds.drift


## How many streaks are on screen (tests).
func streak_count() -> int:
	return _mmi.multimesh.visible_instance_count


func _process(delta: float) -> void:
	if wind == null:
		return
	_drive_clouds()
	_drive_sway()
	_drive_streaks(delta)


## Clouds ride the wind aloft. Not at its true speed up there, which would
## send them racing: enough that a glance up tells you which way and how hard.
func _drive_clouds() -> void:
	if clouds == null:
		return
	if wind.is_calm():
		clouds.drift = _cloud_calm
		return
	var w: Vector3 = wind.head()
	var d := Vector2(w.x, w.z)
	clouds.drift = d.normalized() * (1.2 + d.length() * 0.9)


## Flowers: lean the way the wind goes, further and quicker the harder it
## blows. One material for every flower (flora.gd), rebuilt with each world.
func _drive_sway() -> void:
	if terrain == null or terrain.flora == null:
		return
	var mat: ShaderMaterial = terrain.flora.sway_material()
	if mat == null:
		return
	if wind.is_calm():
		mat.set_shader_parameter("sway_strength", SWAY_CALM)
		mat.set_shader_parameter("sway_speed", SWAY_SPEED_CALM)
		mat.set_shader_parameter("wind_dir", SWAY_DIR_CALM)
		return
	var w: Vector3 = wind.head()
	var k := clampf(w.length() / 13.4, 0.0, 1.0)           # 30 mph = flat out
	mat.set_shader_parameter("sway_strength", lerpf(SWAY_CALM, SWAY_GALE, k))
	mat.set_shader_parameter("sway_speed", lerpf(SWAY_SPEED_CALM, SWAY_SPEED_GALE, k))
	mat.set_shader_parameter("wind_dir", Vector2(w.x, w.z).normalized())


func _drive_streaks(delta: float) -> void:
	var mm: MultiMesh = _mmi.multimesh
	var windy: bool = streaks_on and not wind.is_calm() and camera != null and terrain != null
	_shown = move_toward(_shown, 1.0 if windy else 0.0, delta * 1.5)
	if _shown <= 0.0:
		mm.visible_instance_count = 0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = camera
	# Mostly in front of you: that is where you are looking, and throwing.
	var ahead := -cam.global_transform.basis.z
	ahead.y = 0.0
	var centre := cam.global_position + ahead.normalized() * BOX.x * 0.3 if ahead.length() > 0.01 \
		else cam.global_position
	var head: Vector3 = wind.head()
	var n := 0
	for i in COUNT:
		_age[i] += delta
		var p: Vector3 = _pos[i]
		var off := p - centre
		if _age[i] >= _life[i] or absf(off.x) > BOX.x * 0.5 or absf(off.z) > BOX.z * 0.5:
			p = _spawn(centre, head)
			_pos[i] = p
			_age[i] = 0.0
			_life[i] = _rng.randf_range(LIFE.x, LIFE.y)
		var ground: float = terrain.height_at(p.x, p.z)
		var v: Vector3 = wind.at_height(p.y - ground)
		p += v * delta
		p.y = maxf(p.y, ground + LOW * 0.5)                  # ride over a rise, not through it
		_pos[i] = p
		var speed := v.length()
		if speed < 0.05:
			continue
		# In and out softly, so they never pop.
		var t: float = _age[i] / _life[i]
		var fade := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.7, 1.0, t))
		# ... and never a white bar across your face.
		fade *= smoothstep(NEAR.x, NEAR.y, p.distance_to(cam.global_position))
		var z := v / speed
		var x := z.cross(Vector3.UP).normalized()
		var y := x.cross(z)
		var basis := Basis(x * THICK, y * THICK, z * maxf(speed * STRETCH, THICK * 2.0))
		mm.set_instance_transform(n, Transform3D(basis, p))
		mm.set_instance_color(n, Color(COLOR, ALPHA * fade * _shown))
		n += 1
	mm.visible_instance_count = n


## A fresh streak: anywhere in the box, nudged upwind so it has room to run,
## and a little more often low down, where the disc flies.
func _spawn(centre: Vector3, head: Vector3) -> Vector3:
	var p := centre + Vector3(_rng.randf_range(-0.5, 0.5) * BOX.x, 0.0,
		_rng.randf_range(-0.5, 0.5) * BOX.z)
	if head.length() > 0.1:
		p -= head.normalized() * BOX.x * 0.15
	var ground: float = terrain.height_at(p.x, p.z)
	p.y = ground + LOW + pow(_rng.randf(), 1.5) * BOX.y
	return p
