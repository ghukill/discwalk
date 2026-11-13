extends RefCounted
## The wind: one moving body of air over the whole course.
##
## Three things make it up (the why, and what it does to a disc: docs/PHYSICS.md):
##
## - A MEAN wind: a speed and the compass bearing it blows FROM, like a
##   forecast ("10 mph from the west"). The speed is what you would feel on
##   your face: it is true at head height (REF_HEIGHT).
## - A PROFILE with height. Wind is slowed by the ground, so it is lighter at
##   your ankles and stronger above the trees: the standard log law over
##   rough grass. A disc skimming the ground gets ~0.8x the wind you feel, one
##   thrown 10 m up ~1.4x. That is why a high throw gets carried off and a low
##   one "stays under the wind".
## - GUSTS: the speed breathes by +-gustiness and the direction swings a few
##   degrees, slowly (2-17 s), the same everywhere at once.
##
## A flying disc never sees the wind as a force. The flight model works on the
## disc's velocity THROUGH THE AIR, so the wind is simply subtracted first
## (flying_disc.gd, flight_sim.gd). Headwinds lifting and flipping a disc,
## tailwinds dropping it, crosswinds getting under a tilted one: all of that
## falls out of the same lift, drag and moment tables.
##
## Everything here is deterministic: the same clock gives the same gust.

const MPH_PER_MS := 2.2369363
const REF_HEIGHT := 2.0              ## m above the ground where `speed` is true (head height).
const ROUGHNESS := 0.05              ## m. Log-law roughness length: rough grass, scattered trees.
const TOP := 100.0                   ## m. The profile stops growing here.
## F steps through these (mph at head height). Roughly Beaufort 0, 2, 3, 4, 5, 7.
const PRESETS := [
	{"name": "calm", "mph": 0.0},
	{"name": "light", "mph": 5.0},
	{"name": "breezy", "mph": 10.0},
	{"name": "windy", "mph": 15.0},
	{"name": "strong", "mph": 20.0},
	{"name": "gale", "mph": 30.0},
]
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

signal changed

var speed := 0.0                     ## Mean speed at REF_HEIGHT (m/s). 0 = calm.
## Compass bearing the wind blows FROM (deg): 0 = north (-Z), 90 = east (+X),
## the same card as the heading dial. West by default: Michigan's prevailing
## wind, and where these glacial hills came from.
var from_deg := 270.0
var gustiness := 0.2                 ## Gusts: speed swings by this fraction. 0 = dead steady.
var veer := 10.0                     ## Gusts: direction swing (deg) at gustiness 0.2.
var clock := 0.0                     ## s. advance() moves it; gusts are a function of it.

var _head := Vector3.ZERO            ## The wind right now at REF_HEIGHT (cached by advance()).


## Move the gusts on. Call once per physics tick.
func advance(dt: float) -> void:
	clock += dt
	_refresh()


func is_calm() -> bool:
	return speed < 0.01


## Speed multiplier at `h` metres above the ground: 1 at head height, less
## below, more above (log law). Nothing at all in the grass itself.
static func profile(h: float) -> float:
	if h <= ROUGHNESS:
		return 0.0
	return log(minf(h, TOP) / ROUGHNESS) / log(REF_HEIGHT / ROUGHNESS)


## The wind (m/s, a velocity: where the air is going) `h` metres above the
## ground, right now.
func at_height(h: float) -> Vector3:
	if speed < 0.01:
		return Vector3.ZERO
	return _head * profile(h)


## The wind you feel: at head height, gusts and all. What the HUD reads.
func head() -> Vector3:
	return _head


## Unit vector the MEAN wind blows toward.
func mean_dir() -> Vector3:
	return to_dir(from_deg)


## How strong the gust is right now, as a factor on the mean speed.
func gust() -> float:
	var t := clock
	return 1.0 + gustiness * (0.55 * sin(t * TAU / 11.3 + 1.3)
		+ 0.30 * sin(t * TAU / 4.7 + 4.1) + 0.15 * sin(t * TAU / 1.9 + 0.4))


## How far the direction has swung right now (deg, + = veering clockwise).
func swing() -> float:
	var t := clock
	return veer * (gustiness / 0.2) * (0.7 * sin(t * TAU / 17.0 + 2.2) + 0.3 * sin(t * TAU / 6.1 + 5.0))


## Unit vector a wind FROM compass bearing `deg` blows toward.
static func to_dir(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(-sin(a), 0.0, cos(a))


## Compass bearing (deg, 0..360) a wind blowing along `v` comes FROM.
static func bearing_from(v: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(-v.x, v.z)), 360.0)


func set_speed_mph(mph: float) -> void:
	speed = maxf(mph, 0.0) / MPH_PER_MS
	_refresh()
	changed.emit()


func set_from(deg: float) -> void:
	from_deg = fposmod(deg, 360.0)
	_refresh()
	changed.emit()


func set_gustiness(g: float) -> void:
	gustiness = clampf(g, 0.0, 0.6)
	_refresh()
	changed.emit()


## The preset the mean speed sits on (or the nearest one below it).
func preset() -> int:
	var mph := speed * MPH_PER_MS
	var best := 0
	for i in PRESETS.size():
		if mph >= float(PRESETS[i].mph) - 0.01:
			best = i
	return best


## Step the strength up (+1) or down (-1) through PRESETS, wrapping round.
func cycle(step := 1) -> void:
	set_speed_mph(float(PRESETS[posmod(preset() + step, PRESETS.size())].mph))


## Turn the wind by `deg` (clockwise on the compass).
func turn(deg: float) -> void:
	set_from(from_deg + deg)


## "calm", or "breezy" and friends.
func strength_name() -> String:
	return PRESETS[preset()].name


## "west", "north-east"...: where it comes from, to the nearest of eight.
func from_name() -> String:
	return COMPASS[posmod(int(round(from_deg / 45.0)), 8)]


## How the wind sits against a throw heading `fwd` (flat): "head", "tail",
## "L→R" (pushing the disc from left to right), and the quarters between.
## A golfer's shorthand, and the first thing to know before picking a disc.
static func relative_name(wind: Vector3, fwd: Vector3) -> String:
	var w := Vector2(wind.x, wind.z)
	var f := Vector2(fwd.x, fwd.z)
	if w.length() < 0.01 or f.length() < 0.01:
		return ""
	w = w.normalized()
	f = f.normalized()
	var along := w.dot(f)                       # + = tailwind
	var across := f.x * w.y - f.y * w.x         # + = blowing to your right (Godot: +X right when facing -Z)
	var parts := []
	if absf(along) > 0.38:
		parts.append("tail" if along > 0.0 else "head")
	if absf(across) > 0.38:
		parts.append("L→R" if across > 0.0 else "R→L")
	return " ".join(parts)


## `--wind=10` or `--wind=10@270`: mph at head height, and optionally the
## bearing it blows from. Returns false if it made no sense.
func parse(text: String) -> bool:
	var mph := text.get_slice("@", 0)
	if not mph.is_valid_float():
		return false
	if text.contains("@"):
		var deg := text.get_slice("@", 1)
		if not deg.is_valid_float():
			return false
		from_deg = fposmod(deg.to_float(), 360.0)
	set_speed_mph(mph.to_float())
	return true


func _refresh() -> void:
	if speed < 0.01:
		_head = Vector3.ZERO
		return
	_head = to_dir(from_deg + swing()) * speed * gust()
