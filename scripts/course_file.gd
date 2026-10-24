extends RefCounted
## Courses from files: a folder with a course.json (and a heightmap, trees...)
## that terrain.gd builds instead of a generated world. The format is in
## docs/COURSE_FORMAT.md; this reads it, fills in the defaults, and says
## what's wrong with it (tools/course_check.gd prints the same problems).
##
## Courses are found in every folder of SEARCH, then `--courses-dir=<path>`
## (after `--` on the command line). The folder's name is the course's id; a
## later folder with the same id replaces an earlier one, so your own copy of
## a built-in course wins.
##
## Coordinates are course metres: x east, z south, from the north-west corner
## of the course's `size`. A layout is the part of the course that gets built
## (its `bounds`) and the holes played there.

const SEARCH := ["res://data/courses", "user://courses"]
const FORMAT := 1
const BOUNDS_MARGIN := 40.0            ## Default layout bounds: holes' box plus this (m).
const KINDS := ["giant", "big", "medium", "sapling"]
const FORMS := ["spreading", "tall", "forked", "leaning", "sapling",
	"eucalyptus", "palm"]
const PROPS := ["bench", "clubhouse"]
## Made ground, as terrain.gd's paint kinds.
const SURFACES := {"dirt": 6, "asphalt": 7, "concrete": 8}


## Folders that might hold courses, in search order.
static func search_dirs() -> Array[String]:
	var out: Array[String] = []
	out.assign(SEARCH)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--courses-dir="):
			out.append(a.get_slice("=", 1))
	return out


## Every course found: [{id, name, dir, layouts: [{name, slug}]}], by name.
## Folders whose course.json won't load are skipped (with a warning).
static func list() -> Array[Dictionary]:
	var by_id := {}
	for root in search_dirs():
		if not DirAccess.dir_exists_absolute(root):
			continue
		for sub in DirAccess.get_directories_at(root):
			var dir := root.path_join(sub)
			if not FileAccess.file_exists(dir.path_join("course.json")):
				continue
			var c := read(dir)
			if c.errors.size() > 0:
				push_warning("course %s: %s" % [dir, c.errors[0]])
				continue
			var layouts := []
			for l: Dictionary in c.layouts:
				layouts.append({"name": l.name, "slug": l.slug})
			by_id[sub] = {"id": sub, "name": c.name, "dir": dir, "layouts": layouts}
	var out: Array[Dictionary] = []
	out.assign(by_id.values())
	out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


## The folder of the course with this id (or a path to a course folder).
static func find(id_or_dir: String) -> String:
	if FileAccess.file_exists(id_or_dir.path_join("course.json")):
		return id_or_dir
	var found := ""
	for root in search_dirs():
		var dir: String = root.path_join(id_or_dir)
		if FileAccess.file_exists(dir.path_join("course.json")):
			found = dir
	return found


## Reads <dir>/course.json into a Dictionary with every default filled in:
## name, size (Vector2), terrain {heightmap, height_min, height_max,
## vertical_scale}, foliage {leaves: [Color], bark: Color, flowers: float},
## props [{kind, at: Vector2, yaw, color}],
## surfaces [{kind: int, width, path: [Vector2], poly: [Vector2]}],
## water [{at: Vector2, radius, level (or NAN)}], trees
## [{at: Vector2, crown, kind, form}], holes [{n, tee, basket, aim: Vector2}],
## layouts [{name, slug, holes: [n...], bounds: Rect2, block_size (or 0)}],
## plus errors / warnings (Array of String). Usable when errors is empty.
static func read(dir: String) -> Dictionary:
	var c := {"dir": dir, "errors": [], "warnings": [], "name": dir.get_file(),
		"size": Vector2.ZERO, "terrain": {}, "foliage": {"leaves": [], "bark": null, "flowers": 1.0},
		"water": [], "trees": [], "props": [], "surfaces": [], "holes": [], "layouts": []}
	var text := FileAccess.get_file_as_string(dir.path_join("course.json"))
	if text == "":
		c.errors.append("no course.json in %s" % dir)
		return c
	var json := JSON.new()
	if json.parse(text) != OK:
		c.errors.append("course.json line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return c
	var d = json.data
	if not d is Dictionary:
		c.errors.append("course.json must be an object")
		return c
	if int(d.get("format", FORMAT)) > FORMAT:
		c.warnings.append("format %s is newer than this game reads (%d)" % [d.format, FORMAT])
	c.name = str(d.get("name", c.name))
	var size = _vec(d.get("size"))
	if size == null or size.x <= 0 or size.y <= 0:
		c.errors.append("size must be [x, z] in metres, both > 0")
		return c
	c.size = size

	var t = d.get("terrain", {})
	if not t is Dictionary:
		c.errors.append("terrain must be an object")
		return c
	c.terrain = {"heightmap": str(t.get("heightmap", "")),
		"height_min": float(t.get("height_min", 0.0)), "height_max": float(t.get("height_max", 0.0)),
		"vertical_scale": float(t.get("vertical_scale", 1.0))}
	c.foliage = _foliage(d.get("foliage", {}))
	c.props = _props(d.get("props", []), c)
	c.surfaces = _surfaces(d.get("surfaces", []), c)
	if c.terrain.heightmap != "":
		if not FileAccess.file_exists(dir.path_join(c.terrain.heightmap)):
			c.errors.append("terrain.heightmap: no file %s" % c.terrain.heightmap)
		if c.terrain.height_max < c.terrain.height_min:
			c.errors.append("terrain: height_max is below height_min")

	for i in _arr(d.get("water", [])).size():
		var w = d.water[i]
		var at = _vec(w.get("at")) if w is Dictionary else null
		if at == null or float(w.get("radius", 0)) <= 0:
			c.errors.append("water[%d]: needs at [x, z] and a radius > 0" % i)
			continue
		c.water.append({"at": at, "radius": float(w.radius),
			"level": float(w.get("level", NAN))})

	var trees = d.get("trees", [])
	if trees is String:
		var tj := JSON.new()
		if tj.parse(FileAccess.get_file_as_string(dir.path_join(trees))) != OK:
			c.errors.append("trees: can't read %s (%s)" % [trees, tj.get_error_message()])
			trees = []
		else:
			trees = tj.data
	for i in _arr(trees).size():
		var tr = trees[i]
		var at = _vec(tr.get("at")) if tr is Dictionary else null
		if at == null:
			c.errors.append("trees[%d]: needs at [x, z]" % i)
			continue
		var kind := str(tr.get("kind", "medium"))
		if kind not in KINDS:
			c.warnings.append("trees[%d]: kind %s isn't one of %s; using medium" % [i, kind, KINDS])
			kind = "medium"
		var form := str(tr.get("form", "sapling" if kind == "sapling" else "spreading"))
		if form not in FORMS:
			c.warnings.append("trees[%d]: form %s isn't one of %s; using spreading" % [i, form, FORMS])
			form = "spreading"
		var crown: float = tr.get("crown", {"giant": 7.0, "big": 5.0, "medium": 3.6, "sapling": 1.8}[kind])
		# leaf: which entry of foliage.leaves this tree takes its colour from
		# (-1 = any). Lets one course hold several species.
		c.trees.append({"at": at, "crown": crown, "kind": kind, "form": form,
			"leaf": int(tr.get("leaf", -1))})

	var numbers := {}
	for i in _arr(d.get("holes", [])).size():
		var h = d.holes[i]
		if not h is Dictionary:
			c.errors.append("holes[%d] must be an object" % i)
			continue
		var tee = _vec(h.get("tee"))
		var basket = _vec(h.get("basket"))
		var n := int(h.get("n", i + 1))
		if tee == null or basket == null:
			c.errors.append("hole %d: needs tee and basket as [x, z]" % n)
			continue
		if numbers.has(n):
			c.errors.append("hole %d is listed twice" % n)
		numbers[n] = true
		var aim = _vec(h.get("aim"))
		c.holes.append({"n": n, "tee": tee, "basket": basket, "aim": aim if aim != null else basket})
		for p in [tee, basket]:
			if p.x < 0 or p.y < 0 or p.x > size.x or p.y > size.y:
				c.errors.append("hole %d: %s is outside the course's size" % [n, p])
		if tee.distance_to(basket) < 5.0:
			c.warnings.append("hole %d: tee and basket are only %.1f m apart" % [n, tee.distance_to(basket)])
	c.holes.sort_custom(func(a, b): return a.n < b.n)

	var layouts = _arr(d.get("layouts", []))
	if layouts.is_empty():
		layouts = [{"name": "Full course"}]
	for i in layouts.size():
		var l = layouts[i]
		if not l is Dictionary or not l.has("name"):
			c.errors.append("layouts[%d]: needs a name" % i)
			continue
		var want = l.get("holes", null)
		var ns: Array[int] = []
		if want == null:
			for h in c.holes:
				ns.append(h.n)
		else:
			for n in _arr(want):
				if not numbers.has(int(n)):
					c.errors.append("layout %s: no hole %s" % [l.name, n])
				else:
					ns.append(int(n))
		var b := Rect2()
		var bv = l.get("bounds", null)
		if bv is Array and bv.size() == 4:
			b = Rect2(float(bv[0]), float(bv[1]), float(bv[2]) - float(bv[0]), float(bv[3]) - float(bv[1]))
			if b.size.x <= 0 or b.size.y <= 0:
				c.errors.append("layout %s: bounds must be [x0, z0, x1, z1] with x1 > x0, z1 > z0" % l.name)
		elif bv != null:
			c.errors.append("layout %s: bounds must be [x0, z0, x1, z1]" % l.name)
		else:
			b = _hole_box(c.holes, ns, size)
		b = b.intersection(Rect2(Vector2.ZERO, size))
		for h in c.holes:
			if h.n in ns:
				for p in [h.tee, h.basket, h.aim]:
					if not b.grow(-2.0).has_point(p):
						c.errors.append("layout %s: hole %d's %s is outside its bounds" % [l.name, h.n, p])
		var bs := float(l.get("block_size", 0.0))
		if bs != 0.0 and (bs < 0.125 or bs > 4.0):
			c.errors.append("layout %s: block_size %s isn't between 0.125 and 4" % [l.name, bs])
		c.layouts.append({"name": str(l.name), "slug": slug(str(l.name)), "holes": ns, "bounds": b,
			"block_size": bs})
	return c


## The layout called `name` (its name or slug, any case); the first if "".
static func layout(c: Dictionary, name: String) -> Dictionary:
	if c.layouts.is_empty():
		return {}
	for l in c.layouts:
		if name == "" or l.slug == slug(name):
			return l
	return {}


## "Front 9" -> "front-9".
static func slug(name: String) -> String:
	var out := ""
	for ch in name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	return out.trim_prefix("-").trim_suffix("-")


## The heightmap as 0..1 values: {w, h, v: PackedFloat32Array (row-major,
## row 0 = north)}, or {} if it won't load. 16-bit grayscale PNGs are read
## here (Godot's own loader keeps only 8 bits); anything else goes through
## Image (8-bit grayscale, or the red channel).
static func heightmap(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 33 and bytes[24] == 16 and bytes[25] == 0 and bytes[28] == 0 \
			and bytes.slice(12, 16).get_string_from_ascii() == "IHDR":
		var out := _png16(bytes)
		if not out.is_empty():
			return out
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return {}
	img.convert(Image.FORMAT_R8)
	var data := img.get_data()
	var v := PackedFloat32Array()
	v.resize(data.size())
	for i in data.size():
		v[i] = data[i] / 255.0
	return {"w": img.get_width(), "h": img.get_height(), "v": v}


## Decodes a 16-bit grayscale, non-interlaced PNG.
static func _png16(bytes: PackedByteArray) -> Dictionary:
	var w := _u32(bytes, 16)
	var h := _u32(bytes, 20)
	var idat := PackedByteArray()
	var i := 8
	while i + 8 <= bytes.size():
		var n := _u32(bytes, i)
		var kind := bytes.slice(i + 4, i + 8).get_string_from_ascii()
		if kind == "IDAT":
			idat.append_array(bytes.slice(i + 8, i + 8 + n))
		elif kind == "IEND":
			break
		i += 12 + n
	var raw := idat.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	var stride := w * 2
	if raw.size() < h * (stride + 1):
		return {}
	var prev := PackedByteArray()
	prev.resize(stride)
	var cur := PackedByteArray()
	cur.resize(stride)
	var v := PackedFloat32Array()
	v.resize(w * h)
	for y in h:
		var o := y * (stride + 1)
		var f := raw[o]
		o += 1
		for x in stride:
			var a := cur[x - 2] if x >= 2 else 0
			var b := prev[x]
			var c := prev[x - 2] if x >= 2 else 0
			var p := raw[o + x]
			match f:
				1: p += a
				2: p += b
				3: p += (a + b) >> 1
				4:
					var pa := absi(b - c)
					var pb := absi(a - c)
					var pc := absi(a + b - 2 * c)
					p += a if pa <= pb and pa <= pc else (b if pb <= pc else c)
			cur[x] = p & 0xff
		for x in w:
			v[y * w + x] = ((cur[x * 2] << 8) | cur[x * 2 + 1]) / 65535.0
		var t := prev
		prev = cur
		cur = t
	return {"w": w, "h": h, "v": v}


static func _u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


## The box round a layout's holes (tees, baskets, aim points), plus margin.
static func _hole_box(holes: Array, ns: Array[int], size: Vector2) -> Rect2:
	var b := Rect2()
	var first := true
	for h in holes:
		if h.n not in ns:
			continue
		for p in [h.tee, h.basket, h.aim]:
			if first:
				b = Rect2(p, Vector2.ZERO)
				first = false
			else:
				b = b.expand(p)
	if first:
		return Rect2(Vector2.ZERO, size)
	return b.grow(BOUNDS_MARGIN)


static func _vec(v):
	if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		return Vector2(v[0], v[1])
	return null


static func _arr(v) -> Array:
	return v if v is Array else []


## What a course's trees look like: a leaf palette its trees index into, the
## bark colour, and how much of the usual wildflower scatter to keep.
##
## All optional. Without it a course gets the oak greens and brown bark, which
## is right for Michigan and wrong for a canyon in San Diego.
##
##   "foliage": {"leaves": [[0.42, 0.3, 0.62], ...], "bark": [0.55, 0.5, 0.45],
##               "flowers": 0.05}
static func _foliage(f) -> Dictionary:
	var out := {"leaves": [], "bark": null, "flowers": 1.0}
	if not f is Dictionary:
		return out
	for c in f.get("leaves", []):
		var col = _color(c)
		if col != null:
			out.leaves.append(col)
	out.bark = _color(f.get("bark", null))
	out.flowers = clampf(float(f.get("flowers", 1.0)), 0.0, 4.0)
	return out


## [r, g, b] in 0..1, or null.
static func _color(c):
	if not (c is Array) or c.size() < 3:
		return null
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Course furniture (props.gd): benches, the pro shop. Each is
##   {"kind": "bench"|"clubhouse", "at": [x, z], "yaw": deg, "color": name}
## `at` is where it stands in course metres; it sits on the ground there.
static func _props(list, c: Dictionary) -> Array:
	var out: Array = []
	if not list is Array:
		c.warnings.append("props must be a list")
		return out
	for i in list.size():
		var p = list[i]
		var at = _vec(p.get("at")) if p is Dictionary else null
		if at == null:
			c.errors.append("props[%d]: needs at [x, z]" % i)
			continue
		var kind := str(p.get("kind", ""))
		if kind not in PROPS:
			c.errors.append("props[%d]: kind %s isn't one of %s" % [i, kind, PROPS])
			continue
		out.append({"kind": kind, "at": at, "yaw": float(p.get("yaw", 0.0)),
			"color": str(p.get("color", "teal"))})
	return out


## Roads, paths and car parks: ground the course paints under itself, so a
## park has a road beside it and a car park you can walk on instead of grass
## to the horizon. Either a polyline with a width, or a polygon.
##
##   {"kind": "asphalt", "width": 16, "path": [[307, 277], [272, 330], ...]}
##   {"kind": "dirt", "poly": [[200, 398], [229, 342], [252, 354], [223, 410]]}
static func _surfaces(list, c: Dictionary) -> Array:
	var out: Array = []
	if not list is Array:
		c.warnings.append("surfaces must be a list")
		return out
	for i in list.size():
		var s = list[i]
		if not s is Dictionary:
			c.errors.append("surfaces[%d] must be an object" % i)
			continue
		var kind := str(s.get("kind", ""))
		if not SURFACES.has(kind):
			c.errors.append("surfaces[%d]: kind %s isn't one of %s" % [i, kind, SURFACES.keys()])
			continue
		var path: Array = []
		for v in s.get("path", []):
			var p = _vec(v)
			if p != null:
				path.append(p)
		var poly: Array = []
		for v in s.get("poly", []):
			var p = _vec(v)
			if p != null:
				poly.append(p)
		if path.size() < 2 and poly.size() < 3:
			c.errors.append("surfaces[%d]: needs a path of 2+ points or a poly of 3+" % i)
			continue
		out.append({"kind": SURFACES[kind], "width": maxf(float(s.get("width", 3.0)), 0.5),
			"path": path, "poly": poly})
	return out
