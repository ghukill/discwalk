# Course format

A course you can build outside the game: a folder with a `course.json`, a heightmap, and (usually) a tree list. discwalk builds it into a voxel world with tee pads, baskets and water. This page is the whole spec: if you're an agent asked to make a course, read it top to bottom, then follow [Making a course](#making-a-course).

The example used throughout is the real one in [`data/courses/ponds-at-lakeshore/`](../data/courses/ponds-at-lakeshore/).

## Where courses live

```
<courses dir>/
  ponds-at-lakeshore/        <- the folder name is the course's id
    course.json              <- required
    height.png               <- the ground (optional: no heightmap = flat)
    trees.json               <- the trees (optional; or inline in course.json)
    aerial.png               <- anything else is ignored by the game (handy for tracing)
```

The game looks in these folders, in order, and lists every course it finds in the menu (one entry per [layout](#layouts)):

1. `res://data/courses/`: the courses that ship with the game (this repo).
2. `user://courses/`: your own. On macOS that's `~/Library/Application Support/Godot/app_userdata/discwalk/courses/`, on Linux `~/.local/share/godot/app_userdata/discwalk/courses/`.
3. `--courses-dir=<path>` on the command line (after `--`), for a folder anywhere.

A later folder's course replaces an earlier one with the same id, so a copy in `user://courses/` overrides the built-in one. Start straight on a course with `--course=<id>` (or a path to the folder) and optionally `--layout=<name>`:

```sh
bin/run.sh --course=ponds-at-lakeshore --layout="back 9" --mode=course
bin/run.sh --courses-dir=~/my-courses --course=backyard
```

### How a course gets loaded

All of it is in [`scripts/course_file.gd`](../scripts/course_file.gd) (finding and reading) and [`scripts/terrain.gd`](../scripts/terrain.gd) (building).

1. **Finding.** `CourseFile.search_dirs()` is the folders above, in order. `CourseFile.list()` looks at every sub-folder of each that has a `course.json`, reads it, and keeps it by folder name (so a later folder wins). A course with errors is left out of the list with a warning in the console; it doesn't stop the others loading.
2. **The menu.** The menu asks `list()` once, when the game starts, and adds one place per layout after Glacial hills and the Distance course. A course you drop into `user://courses/` while the game is running shows up next launch.
3. **Picking one.** Choosing a place (or `--course=` / `--layout=` on the command line) sets the terrain's `world_kind = "course"`, `course_id` and `layout_name`, then rebuilds the world. `CourseFile.find(id)` turns the id into a folder: a path to a folder with a `course.json` is used as is, otherwise the last search folder holding `<id>/course.json` wins.
4. **Reading.** `CourseFile.read(dir)` parses `course.json`, loads the tree file if `trees` names one, fills in every default (layouts, bounds, hole numbers, aim points, tree sizes) and collects `errors` and `warnings`. Errors (no `size`, a hole without a tee...) mean the course can't be built: the game says why and falls back to Glacial hills. `CourseFile.layout(course, name)` picks the layout (by [slug](#layouts)); an unknown name falls back to the first one.
5. **Building.** The layout's `bounds` become the world's size and its `block_size` the voxel size (unless `--block-size=` was given). The heightmap is read with `CourseFile.heightmap()` (16-bit PNGs are decoded by hand: Godot's own loader keeps only 8 bits), stretched over `size` and cut to the bounds; tees are levelled, water filled, then trees, tees and baskets placed, as for a generated world.

The course is read straight from its files every time it's built, through `FileAccess`, not Godot's resource importer. That's why the PNGs need care when a course ships with the game (below).

### Shipping a course with the game

A course in `user://courses/` or `--courses-dir` is just files; nothing else is needed. A course added to **this repo** under `data/courses/` also needs:

- **`height.png.import`** saying `importer="keep"`, so the export ships the raw PNG (the game reads its bytes itself; an imported texture would be 8-bit and not where the game looks).
- **`aerial.png.import`** (and the same for any other image that's only there for tracing) saying `importer="skip"`, so it isn't imported or shipped at all.

Both are two lines:

```
[remap]

importer="keep"
```

Copy them from an existing course. `.gitignore` ignores `*.import` except `data/courses/*/*.import`, so they get committed. `course.json` and the tree file ship because `export_presets.cfg` has `include_filter="*.json"`. Then run the [checker](#the-checker-and-the-preview) on the new course.

## Coordinates

Everything is in **metres**, on a flat map of the course seen from above, **north up**:

- `x` runs **east**, `z` runs **south**, from `[0, 0]` at the **north-west** corner.
- The course is `size: [x, z]` metres. Every position in the file (tees, baskets, trees, water) is `[x, z]` inside it.
- Heights are in whatever metres your heightmap uses (sea level is fine): `height_min` and `height_max` say what black and white mean.

That's the same way round as an image: pixel `(col, row)` of a north-up map is at `x = col * metres_per_pixel`, `z = row * metres_per_pixel`. So you can read positions off an aerial photo or a map screenshot of the course's box.

## course.json

```json
{
 "format": 1,
 "name": "The Ponds at Lakeshore",
 "location": "Ypsilanti, Michigan",
 "about": "Free text: what it is, where the data came from.",
 "size": [618, 598],
 "geo": {"upper_left": [42.215551, -83.56532], "lower_right": [42.210182, -83.557825]},
 "terrain": {"heightmap": "height.png", "height_min": 211.1, "height_max": 219.8},
 "water": [
  {"at": [451, 386], "radius": 40, "level": 213.85}
 ],
 "trees": "trees.json",
 "holes": [
  {"n": 1, "tee": [174.6, 84.1], "basket": [254.1, 138.3]},
  {"n": 5, "tee": [584.7, 502.3], "basket": [515.4, 540.0], "aim": [526.1, 508.1]}
 ],
 "layouts": [
  {"name": "Front 9", "holes": [1, 2, 3, 4, 5, 6, 7, 8, 9], "block_size": 0.5},
  {"name": "Back 9", "holes": [10, 11, 12, 13, 14, 15, 16, 17, 18], "block_size": 0.5}
 ]
}
```

(Shortened: the real file lists all 18 holes and has a third layout, Full 18.)

| Field | | Meaning |
|---|---|---|
| `format` | optional | `1`. The game warns about a newer number it doesn't know. |
| `name` | required | Shown in the menu and the HUD. |
| `location`, `about` | optional | For people. Not shown in game (yet). |
| `size` | **required** | `[x, z]`: the course's extent in metres. The heightmap is stretched over exactly this. |
| `geo` | optional | Lat/lon of the upper-left and lower-right corners, if it's a real place. Not used by the game; it records where the box is. |
| `terrain` | optional | The [heightmap](#heightmap). Leave it out for flat ground. |
| `water` | optional | [Ponds and lakes](#water). |
| `trees` | optional | [Trees](#trees): a list, or the name of a JSON file in the folder holding the list. |
| `holes` | optional | [Holes](#holes). A course with none is fine (Free Play only). |
| `layouts` | optional | [Layouts](#layouts). Leave it out and you get one, "Full course", with every hole. |

Unknown fields are ignored, so you can keep notes in the file.

### Heightmap

```json
"terrain": {"heightmap": "height.png", "height_min": 211.1, "height_max": 219.8, "vertical_scale": 1.0}
```

- A **grayscale PNG**, north up, not interlaced. **16-bit is best** (65,536 steps; real elevation needs it). 8-bit works too (256 steps: fine for a hand-painted map with a range of a few tens of metres). A colour PNG uses its red channel.
- It's **stretched over `size`**: any resolution works, and the pixels needn't be square. 1 px per metre is plenty (the game's smallest blocks are 0.25 m and it smooths between pixels).
- Black = `height_min`, white = `height_max` (metres). Pick them to fit your data with a little room; the heightmap uses the range in between.
- `vertical_scale` (default 1) multiplies the relief. A flat park might look better at 1.5 or 2.
- In game, `height_min` sits 4 m above the bottom of the world. The world ends in a **cliff** at the layout's edge, so you see that much (or more) of the ground's side.

To paint one by hand: any editor that saves 16-bit grayscale PNG (Krita, GIMP, Photoshop), or numpy + Pillow (`Image.fromarray(array_uint16).save("height.png")`).

### Water

```json
"water": [{"at": [451, 386], "radius": 40, "level": 213.85}]
```

Each is a circle: centre `at` and `radius` (m). Inside the circle, all ground below `level` (heightmap metres) is under water; ground above it stays dry. So the circle only needs to cover the pond, and the heightmap gives it its shape. Make the circle just big enough: any low ground inside it floods too.

Leave `level` out and the water fills to just under the lowest point of the ground round the circle's edge (like the kettle lakes on generated worlds). That suits a bowl you've pressed into the heightmap yourself.

Lidar heightmaps already have ponds: their surface comes out dead flat. Put `level` a little (5 to 15 cm) above that flat surface.

### Trees

```json
"trees": "trees.json"
```

```json
[
 {"at": [312.4, 98.0], "crown": 3.6, "kind": "medium", "form": "spreading"},
 {"at": [120.0, 210.5], "kind": "big"}
]
```

| Field | | Meaning |
|---|---|---|
| `at` | required | Trunk position `[x, z]`. |
| `kind` | optional | Size class: `giant`, `big`, `medium` (default), `sapling`. Sets trunk height and thickness. |
| `crown` | optional | Crown radius in metres. Default by kind: giant 7, big 5, medium 3.6, sapling 1.8. |
| `form` | optional | Shape: `spreading` (default), `tall` (narrow, reaching up: use it for conifers), `forked`, `leaning`, `sapling`. |

All trees are discwalk's voxel oaks (there are no conifers yet; `tall` is the nearest). Each one's details (exact limbs, lean direction) come from the game, not the file.

The game leaves out trees that would stand in water, on a basket (within 2 m), or hang over a tee pad (within the crown's reach), so a rough list is fine.

Trees are the expensive part of a world: the [build cost](#size-and-build-time) is mostly them. A few hundred per layout is comfortable.

### Holes

```json
{"n": 9, "tee": [444.9, 524.0], "basket": [362.2, 393.5], "aim": [381.1, 450.1]}
```

| Field | | Meaning |
|---|---|---|
| `n` | optional | Hole number. Default: its place in the list, from 1. Numbers must be unique. |
| `tee` | required | Centre of the tee pad `[x, z]`. |
| `basket` | required | Where the basket stands `[x, z]`. |
| `aim` | optional | The point the tee faces. Default: the basket. Use it for a **dogleg**: the corner of the fairway. |

The game paints a grey 1.5 × 3 m pad, turned to face `aim` (snapped to the nearest 45°, since it's painted into the block grid), with the hole number beside it. The basket stands on the ground. Holes are played in number order.

The game levels the ground round each tee (flat for 2.5 m, easing back into the slope by 5 m), like a built tee pad, so tees can sit on a hillside. Baskets aren't levelled: put them on fairly level ground. Keep both out of water and out of trees.

### Layouts

A layout is **the part of the course that gets built and the holes played there**. Each one is its own entry in the menu (`The Ponds at Lakeshore · Back 9`).

```json
{"name": "Back 9", "holes": [10, 11, 12, 13, 14, 15, 16, 17, 18], "bounds": [140, 95, 590, 415], "block_size": 0.5}
```

| Field | | Meaning |
|---|---|---|
| `name` | required | Shown in the menu. `--layout=` matches it in any case, with spaces or dashes (`back-9`). |
| `holes` | optional | Hole numbers, played in number order. Default: all of them. |
| `bounds` | optional | `[x0, z0, x1, z1]`: the box that gets built. Default: the box round the layout's tees, baskets and aim points, plus 40 m all round (and never past `size`). |
| `block_size` | optional | Voxel size for this layout in metres: 0.25, 0.5 or 1 make sense (0.125 to 4 allowed). Default: the game's (0.25 m, or `--block-size=`). `--block-size=` on the command line beats it. Set it for any layout over about 300 m across: at 0.25 m a big layout takes minutes to build and can exceed the physics engine's limits. |

The world ends at the bounds in a cliff, with invisible walls just inside. Layouts may overlap as much as you like: only one is built at a time.

#### Size and build time

A layout is built when you pick it, and big ones take a while. Measured on an M2 Max (expect roughly 1.5× longer on an older laptop):

| Layout (Ponds at Lakeshore) | Area | Trees | Block | Build | Memory |
|---|---|---|---|---|---|
| Back 9 | 440 × 310 m | ~280 | 1 m | 4 s | – |
| Front 9 / Full 18 | 480 × 535 m | ~610 | 1 m | 9 s | – |
| Front 9 / Full 18 | 480 × 535 m | ~610 | 0.5 m | 26 s | 1.5 GB |

For comparison, the generated 256 × 256 m world at 0.25 m takes about a minute and 1.7 GB. Halving the block size makes trees about 7× as many voxels. Rules of thumb: up to about 300 × 300 m at 0.25 m; bigger, use 0.5 m.

## Making a course

### From a real place (US)

```sh
# 1. Ground + aerial photo for a lat/lon box (north-west and south-east corners).
uv run tools/courses/site_from_geo.py --ul 42.215551,-83.565320 --lr 42.210182,-83.557825 \
    --out data/courses/my-course
# -> height.png (1 px/m, 16-bit), aerial.png (2 px/m), site.json (size, height range, geo)

# 2. Trees, guessed from the photo. Look at the preview; edit trees.json if it's wrong.
uv run tools/courses/trees_from_aerial.py data/courses/my-course --preview /tmp/trees.png
#    Too dense to play? --thin 0.3 drops 30% of the woods' trees (lone trees stay).

# 3. Write course.json: size / height_min / height_max / geo from site.json, then water,
#    holes and layouts by hand (positions read off aerial.png: x = col / 2, z = row / 2).

# 4. Check it, then look at it.
G=/Applications/Godot.app/Contents/MacOS/Godot    # or your Godot 4.7 executable
$G --headless --path . --script res://tools/course_check.gd -- my-course
$G --path . --resolution 1280x720 --script res://tools/course_preview.gd -- /tmp/preview --course=my-course --block-size=1
```

`site_from_geo.py` uses [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) elevation (bare-earth lidar, 1 m in most of the US) and [USDA NAIP](https://naip-usdaonline.hub.arcgis.com/) aerial photos, both public domain and free, with no key. Outside the US you'll need other sources; any DEM resampled to a north-up metre grid works.

**Holes from a course map.** Course maps (UDisc, the park's sign, a screenshot) are usually north-up web maps too, so their pixels are a scaled and shifted copy of `aerial.png`'s. Find two or three landmarks in both (a road corner, a lone tree) and fit `x = a * col + b`, `z = a * row + c`. For the Ponds, the course map screenshot came out at 0.29 m per pixel, offset (65, 18) m; lining up the dark tree shapes of both images by cross-correlation found that, and matched the hand-picked landmarks.

### By hand

Paint `height.png` in an image editor (or don't: flat is fine), pick a `size`, and write `course.json`. Positions are just metres from the top-left of your image.

### The checker and the preview

`tools/course_check.gd` reads the course, reports anything malformed, then builds each layout (at 1 m blocks, quick) and checks every hole: tee or basket in water, a tee on a slope, leaves over a tee pad or filling the first 10 m off it. It prints each hole's length and the height difference tee to basket, and ends with `CHECK PASS` or `CHECK FAIL` (exit code 1).

`tools/course_preview.gd` (needs a display) writes `map.png`, the layout from straight above with tees (blue, numbered) and baskets (red), and `tee_<n>.png`, the view from each tee toward its basket (or down the fairway on a dogleg). Use them to see what the numbers don't show: a basket hidden in a grove, a fairway that's a wall of trees.

## Not in the format (yet)

- One tee per hole: no short / long tees or alternate basket positions.
- No par, OB lines, mandos or hazards; water is just water.
- Ground colour is the game's grass everywhere: no paths, roads, sand or buildings.
- Only oaks.
