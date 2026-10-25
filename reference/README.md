# Reference photos

Photographs of the real courses, kept so that `data/courses/<name>` can be
argued with. The lidar says where the ground is and the aerial says roughly
where the trees are; only a photo from the tee says what the hole *feels*
like -- which trees frame it, where the mown grass gives way to bark, how
much sky is left between the canopy and the basket.

Godot skips this whole tree (`.gdignore`), so nothing here ships in a build.

## Layout

    reference/morley-field/
      index.html      contact sheet: open it to label photos by hole
      photos.tsv      photo -> when it was taken -> which hole
      originals/      untouched phone files, ~5MB each (gitignored)
      unsorted/       imported, not yet labelled
      hole-01/ ...    labelled, one folder per hole
      around/         the shop, the car park, the roads: not one hole

The 1400px JPEGs in the hole folders are the working copies -- small enough
to live in git, large enough to read a tree off. Keep the originals; a crop
of a 5712px frame is how you settle an argument about a sign or a bench.

## Adding a session

    python3 tools/courses/import_photos.py morley-field ~/Downloads --day 2026-10-24
    open reference/morley-field/index.html
    python3 tools/courses/import_photos.py morley-field --sort

Phones strip GPS when photos leave the device, so nothing but you knows which
hole a frame came from. The sheet makes that cheap: click a photo, press the
hole number, and it steps to the next one -- a run of shots from one tee is a
held key. Dashed lines mark gaps of more than two and a half minutes, which
is usually the walk to the next tee. Shift-click to see a photo full size.

Press **Copy photos.tsv** when you are done, paste it over `photos.tsv`, and
run `--sort`. Both steps re-run safely: an imported photo is never imported
twice, and a sorted one stays where it is.
