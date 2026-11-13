extends SceneTree
## Prints the flight numbers the docs quote, straight from the flight model
## (flight_sim.gd, the same code the aim arc runs), so nobody has to throw
## and write down. Flat ground, released 1.3 m up, RH backhand, auto spin.
##
##   godot --headless --path . --script res://tools/flight_table.gd
##
## Sections: the "Flights to try" table (docs/DISCS.md), the speed bands
## (throw_setup.gd), soft tosses, full-power throws, wind, and how much the
## damping coefficients matter (docs/PHYSICS.md). Rerun it after changing the
## maths or the tables and paste what moved.

const DiscModel := preload("res://scripts/disc_model.gd")
const FlightSim := preload("res://scripts/flight_sim.gd")
const Wind := preload("res://scripts/wind.gd")

const MPH := 2.2369363

var _models := {}
var _flat := Flat.new()


class Flat:
	func height_at(_x: float, _z: float) -> float:
		return 0.0


func _initialize() -> void:
	for m in DiscModel.load_all():
		_models[m.id] = m
	_flights_to_try()
	_speed_bands()
	_soft_tosses()
	_full_power()
	_wind()
	_damping()
	quit(0)


## One throw along -Z. {carry, left (+ = left), peak (above the ground), t,
## v_land, steep (deg below horizontal at landing)}.
func fly(id: String, speed: float, pitch: float, nose := 0.0, roll := 0.0, wind = null,
		hand := 1.0) -> Dictionary:
	var m = _models[id]
	var ls: Array = DiscModel.launch_state(Vector3.FORWARD, speed, pitch, nose, roll, hand)
	var path: PackedVector3Array = FlightSim.fly(m, Vector3(0, 1.3, 0), ls[0], ls[1],
		DiscModel.auto_spin(speed), hand, _flat, FlightSim.MAX_STEPS, wind)
	var end: Vector3 = path[path.size() - 1]
	var prev: Vector3 = path[path.size() - 2]
	var v := (end - prev) / FlightSim.STEP_DT
	var peak := 0.0
	for p in path:
		peak = maxf(peak, p.y)
	return {"carry": -end.z, "left": -end.x, "peak": peak, "t": (path.size() - 1) * FlightSim.STEP_DT,
		"v_land": v.length(), "steep": rad_to_deg(asin(clampf(-v.y / maxf(v.length(), 0.01), -1.0, 1.0)))}


static func side(left: float) -> String:
	if absf(left) < 0.5:
		return "on line"
	return "%d %s" % [int(round(absf(left))), "L" if left > 0.0 else "R"]


func _cell(r: Dictionary) -> String:
	return "%d m, %s" % [int(round(r.carry)), side(r.left)]


func _flights_to_try() -> void:
	print("\n## Flights to try (10 deg launch, nose 0)\n")
	print("| Disc | Speed | Flat | 10° hyzer | 20° hyzer | 30° hyzer |")
	print("|---|---|---|---|---|---|")
	for row in [["kettle", 16.0], ["drumlin", 19.0], ["esker", 19.0], ["till", 23.0],
			["outwash", 23.0], ["moraine", 24.0], ["erratic", 24.0]]:
		var cells := []
		for roll in [0.0, 10.0, 20.0, 30.0]:
			cells.append(_cell(fly(row[0], row[1], 10.0, 0.0, roll)))
		print("| %s | %d m/s (%d mph) | %s |" % [_models[row[0]].label, int(row[1]),
			int(round(row[1] * MPH)), " | ".join(cells)])
	print("\nErratic, 10° anhyzer: %s" % _cell(fly("erratic", 24.0, 10.0, 0.0, -10.0)))
	print("Moraine at 20 m/s (45 mph), flat: %s;  5° hyzer: %s" % [
		_cell(fly("moraine", 20.0, 10.0)), _cell(fly("moraine", 20.0, 10.0, 0.0, 5.0))])
	print("\nBest carry found per disc and speed (launch 6..24, hyzer 0..40, nose -4..4):")
	for id in ["kettle", "drumlin", "esker", "till", "outwash", "moraine", "erratic"]:
		var line := "  %-8s" % _models[id].label
		for mph in [40.0, 54.0, 65.0, 80.0]:
			var best := {}
			var how := ""
			for pitch in [6.0, 10.0, 14.0, 18.0, 24.0]:
				for roll in [0.0, 10.0, 20.0, 30.0, 40.0]:
					for nose in [-4.0, 0.0, 4.0]:
						var r := fly(id, mph / MPH, pitch, nose, roll)
						if best.is_empty() or r.carry > best.carry:
							best = r
							how = "launch %d, hyzer %d, nose %+d" % [int(pitch), int(roll), int(nose)]
			line += "  %d mph: %d m (%s; %s)" % [int(mph), int(round(best.carry)), side(best.left), how]
		print(line)


func _speed_bands() -> void:
	print("\n## Speed bands (nose +6, 8° hyzer, 10 deg launch): carry at the band edges\n")
	for speed in [12.0, 21.5]:
		var out := []
		for id in ["kettle", "drumlin", "moraine"]:
			out.append("%s %d m" % [_models[id].label, int(round(fly(id, speed, 10.0, 6.0, 8.0).carry))])
		print("  %.1f m/s (%d mph): %s" % [speed, int(round(speed * MPH)), ", ".join(out)])


func _soft_tosses() -> void:
	print("\n## Soft tosses: Kettle, 5° hyzer (carry, peak height, time aloft, landing speed + how steeply)\n")
	print("| Speed | Launch | Nose | Carry | Peak | Aloft | Lands at |")
	print("|---|---|---|---|---|---|---|")
	for row in [[22.0, 10.0, 5.0], [25.0, 5.0, 0.0], [25.0, 10.0, 5.0], [25.0, 15.0, 5.0],
			[25.0, 10.0, 10.0], [28.0, 10.0, 5.0], [28.0, 20.0, 5.0], [32.0, 15.0, 5.0]]:
		var r := fly("kettle", row[0] / MPH, row[1], row[2], 5.0)
		print("| %d mph | %d° | %+d° | %.0f m (%d ft) | %.1f m | %.1f s | %d mph, dropping %d° |" % [
			int(row[0]), int(row[1]), int(row[2]), r.carry, int(round(r.carry * 3.28084)), r.peak, r.t,
			int(round(r.v_land * MPH)), int(round(r.steep))])
	# What the same release would do with no air at all.
	var v := 25.0 / MPH
	var vy := v * sin(deg_to_rad(10.0))
	var t := (vy + sqrt(vy * vy + 2.0 * 9.8 * 1.3)) / 9.8
	print("\n(25 mph at 10° with no air: %.1f m in %.1f s.)" % [v * cos(deg_to_rad(10.0)) * t, t])


func _full_power() -> void:
	print("\n## Full power, 80 mph (35.8 m/s)\n")
	print("| Disc | 10° up, flat | 10° up, 20° hyzer | 20° up, 30° hyzer | 30° up, flat |")
	print("|---|---|---|---|---|")
	var v := 80.0 / MPH
	for id in ["kettle", "drumlin", "esker", "till", "outwash", "moraine", "erratic"]:
		var cells := []
		for c in [[10.0, 0.0], [10.0, 20.0], [20.0, 30.0], [30.0, 0.0]]:
			var r := fly(id, v, c[0], 0.0, c[1])
			cells.append("%s, %.0f s" % [_cell(r), r.t])
		print("| %s | %s |" % [_models[id].label, " | ".join(cells)])


func _wind() -> void:
	print("\n## Wind: steady, mph at head height. Thrown north; carry, drift, peak\n")
	var throws := [
		["Moraine, 54 mph, 10° up, 10° hyzer", "moraine", 24.0, 10.0, 0.0, 10.0, 10.0],
		["Moraine, same, in 20 mph", "moraine", 24.0, 10.0, 0.0, 10.0, 20.0],
		["Erratic, 54 mph, 10° up, flat", "erratic", 24.0, 10.0, 0.0, 0.0, 15.0],
		["Kettle putt, 20 mph, 8° up, nose +5", "kettle", 20.0 / MPH, 8.0, 5.0, 0.0, 15.0],
	]
	print("| Throw | Wind | Calm | Headwind | Tailwind | L→R | R→L |")
	print("|---|---|---|---|---|---|---|")
	for t in throws:
		var cells := []
		for from in [-1.0, 0.0, 180.0, 270.0, 90.0]:
			var w = null
			if from >= 0.0:
				w = Wind.new()
				w.gustiness = 0.0
				w.from_deg = from
				w.set_speed_mph(t[6])
			var r := fly(t[1], t[2], t[3], t[4], t[5], w)
			cells.append("%s, up %.1f m" % [_cell(r), r.peak])
		print("| %s | %d mph | %s |" % [t[0], int(t[6]), " | ".join(cells)])
	print("\nWind profile: x%.2f at 0.5 m, x%.2f at 1 m, x1 at %d m, x%.2f at 5 m, x%.2f at 10 m, x%.2f at 20 m" % [
		Wind.profile(0.5), Wind.profile(1.0), int(Wind.REF_HEIGHT), Wind.profile(5.0),
		Wind.profile(10.0), Wind.profile(20.0)])


func _damping() -> void:
	print("\n## How much the damping matters: Moraine, 24 m/s, 10° up, flat\n")
	var m = _models["moraine"]
	var keep: Array = [m.c_lp, m.c_mq, m.c_nr]
	for k in [0.0, 1.0, 2.0, 4.0]:
		m.c_lp = keep[0] * k
		m.c_mq = keep[1] * k
		print("  roll + pitch damping x%.0f (C_lp = C_mq = %.2f): %s" % [k, m.c_lp, _cell(fly("moraine", 24.0, 10.0))])
	m.c_lp = keep[0]
	m.c_mq = keep[1]
	for k in [0.0, 1.0, 3.0]:
		m.c_nr = keep[2] * k
		print("  spin down x%.0f (C_nr = %.4f): %s" % [k, m.c_nr, _cell(fly("moraine", 24.0, 10.0))])
	m.c_nr = keep[2]
	var q: float = 0.5 * DiscModel.AIR_DENSITY * 24.0 * 24.0 * m.area * m.diameter
	var rate: float = m.diameter / 48.0
	print("  at 24 m/s: wobble dies in ~%.2f s (time constant), spin bleeds %.1f %%/s" % [
		2.0 * m.i_xy / (-(m.c_lp + m.c_mq) * rate * q), -m.c_nr * rate * q / m.i_z * 100.0])
