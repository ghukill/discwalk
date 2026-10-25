# /// script
# requires-python = ">=3.10"
# ///
"""Bring a day's course photos into reference/, then file them by hole.

    python3 tools/courses/import_photos.py morley-field ~/Downloads --day 2026-10-24
    open reference/morley-field/index.html          # click the hole for each
    python3 tools/courses/import_photos.py morley-field --sort

Photos off a phone are 5MB of HEIC apiece: too big to keep in the repo and
unreadable by most tools. The import writes a 1400px JPEG of each one, which
is more than enough to see a tree's shape or where the dirt stops, and parks
the untouched original alongside (originals/ is gitignored).

Which hole a photo came from is the one thing EXIF cannot tell us -- phones
strip GPS on export -- so the import only records when each was taken and
leaves the hole blank in photos.tsv. index.html is a contact sheet in time
order that fills that column in; --sort then moves each labelled photo into
hole-NN/. Both steps are safe to re-run: a photo already imported is skipped,
and sorting an already-sorted photo does nothing.
"""
import argparse
import datetime
import html
import pathlib
import re
import shutil
import struct
import subprocess
import sys

JPEG_PX = 1400
JPEG_Q = 55
SUFFIXES = (".heic", ".heif", ".jpg", ".jpeg", ".png")
# Not a hole: the shop, the car park, the road -- the course around the holes.
AROUND = "around"


# --- EXIF ------------------------------------------------------------------
# Only the capture time, and only from the embedded TIFF block, so that this
# stays stdlib-only and reads HEIC as happily as JPEG.

def _ifd(buf, base, off, bo, want):
    out = {}
    try:
        count = struct.unpack_from(bo + "H", buf, base + off)[0]
    except struct.error:
        return out
    for i in range(count):
        e = base + off + 2 + i * 12
        try:
            tag, typ, num = struct.unpack_from(bo + "HHI", buf, e)
        except struct.error:
            break
        if tag not in want:
            continue
        size = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8}.get(typ, 1) * num
        at = e + 8
        if size > 4:
            at = base + struct.unpack_from(bo + "I", buf, e + 8)[0]
        if typ == 2:
            out[tag] = buf[at:at + num].split(b"\0")[0].decode("ascii", "replace")
        elif typ == 4:
            out[tag] = struct.unpack_from(bo + "I", buf, at)[0]
    return out


def taken_at(path):
    """DateTimeOriginal as 'YYYY-MM-DD HH:MM:SS', or None."""
    buf = path.open("rb").read(3_000_000)
    for sig, bo in ((b"MM\x00\x2a", ">"), (b"II\x2a\x00", "<")):
        pos = -1
        while True:
            pos = buf.find(sig, pos + 1)
            if pos < 0:
                break
            try:
                first = struct.unpack_from(bo + "I", buf, pos + 4)[0]
            except struct.error:
                continue
            top = _ifd(buf, pos, first, bo, {0x0132, 0x8769})
            if 0x8769 not in top:
                continue
            stamp = _ifd(buf, pos, top[0x8769], bo, {0x9003}).get(0x9003)
            stamp = stamp or top.get(0x0132)
            if stamp and len(stamp) == 19:
                return stamp[:10].replace(":", "-") + " " + stamp[11:]
    return None


# --- the sheet -------------------------------------------------------------

def rows_of(tsv):
    if not tsv.exists():
        return []
    out = []
    for line in tsv.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        part = line.split("\t")
        out.append({"file": part[0], "taken": part[1] if len(part) > 1 else "",
                    "hole": part[2].strip() if len(part) > 2 else ""})
    return out


def write_rows(tsv, rows):
    body = ["# photo\ttaken\thole   (hole is 1-19, or '%s' for the shop," % AROUND,
            "#\t\tcar park, roads -- anything that is not one hole)"]
    for r in rows:
        body.append("%s\t%s\t%s" % (r["file"], r["taken"], r["hole"]))
    tsv.write_text("\n".join(body) + "\n")


def gaps(rows):
    """Seconds between each photo and the one before it. A long gap is the
    walk to the next tee, which is the best hint we have at a boundary."""
    out = []
    prev = None
    for r in rows:
        try:
            t = datetime.datetime.strptime(r["taken"], "%Y-%m-%d %H:%M:%S")
        except ValueError:
            out.append(0)
            continue
        out.append(0 if prev is None else int((t - prev).total_seconds()))
        prev = t
    return out


def write_sheet(root, rows, holes):
    cards = []
    for r, gap in zip(rows, gaps(rows)):
        where = (_folder(r["hole"]) if r["hole"] else "unsorted") + "/" + r["file"]
        if gap > 150:
            mins = "%d:%02d" % (gap // 60, gap % 60)
            cards.append('<div class="gap"><span>%s walk</span></div>' % mins)
        cards.append(
            '<figure data-file="%s" data-hole="%s" data-taken="%s">'
            '<img loading="lazy" src="%s" alt="">'
            '<figcaption><b></b><span>%s</span></figcaption></figure>'
            % (html.escape(r["file"]), html.escape(r["hole"]),
               html.escape(r["taken"]), html.escape(where),
               html.escape(r["taken"][11:16])))
    page = SHEET.replace("{CARDS}", "\n".join(cards))
    page = page.replace("{HOLES}", "".join(
        '<button data-h="%s">%s</button>' % (h, h) for h in holes))
    page = page.replace("{COUNT}", str(len(rows)))
    (root / "index.html").write_text(page)


SHEET = """<!doctype html>
<meta charset="utf-8"><title>Course photos</title>
<style>
 :root { --bg:#14161a; --fg:#e8e6e1; --dim:#8d9199; --pick:#6fae5e; }
 body { margin:0; background:var(--bg); color:var(--fg); font:14px/1.4
   ui-sans-serif,-apple-system,Segoe UI,sans-serif; }
 header { position:sticky; top:0; z-index:5; background:#1b1e24;
   border-bottom:1px solid #2a2e36; padding:10px 16px; display:flex;
   gap:12px; align-items:center; flex-wrap:wrap; }
 header h1 { font-size:15px; margin:0 8px 0 0; font-weight:600; }
 #pad { display:flex; gap:4px; flex-wrap:wrap; }
 #pad button { background:#272b33; color:var(--fg); border:1px solid #363b45;
   border-radius:5px; padding:4px 9px; cursor:pointer; font:inherit; }
 #pad button:hover { background:#333842; }
 #pad button.on { background:var(--pick); border-color:var(--pick); color:#0d1410; }
 #out { margin-left:auto; display:flex; gap:8px; align-items:center; }
 #out span { color:var(--dim); }
 .bar { background:#272b33; color:var(--fg); border:1px solid #363b45;
   border-radius:5px; padding:5px 11px; cursor:pointer; font:inherit; }
 main { display:grid; grid-template-columns:repeat(auto-fill,minmax(230px,1fr));
   gap:10px; padding:16px; }
 figure { margin:0; position:relative; cursor:pointer; border-radius:7px;
   overflow:hidden; background:#000; outline:2px solid transparent; }
 figure.sel { outline-color:#d8c56a; }
 figure img { width:100%; aspect-ratio:4/3; object-fit:cover; display:block; }
 figcaption { position:absolute; inset:auto 0 0 0; display:flex;
   justify-content:space-between; padding:4px 7px; font-size:12px;
   background:linear-gradient(transparent,rgba(0,0,0,.8)); }
 figcaption b { color:var(--pick); }
 figcaption span { color:#c9ccd1; }
 .gap { grid-column:1/-1; border-top:1px dashed #3a4049; margin:6px 0 0;
   text-align:center; }
 .gap span { position:relative; top:-9px; background:var(--bg); padding:0 10px;
   color:var(--dim); font-size:12px; }
 dialog { background:#1b1e24; color:var(--fg); border:1px solid #363b45;
   border-radius:8px; max-width:720px; width:90vw; }
 dialog textarea { width:100%; height:50vh; background:#0f1115; color:var(--fg);
   border:1px solid #363b45; border-radius:5px; font:12px ui-monospace,monospace; }
 #big { position:fixed; inset:0; background:rgba(0,0,0,.92); display:none;
   z-index:10; align-items:center; justify-content:center; }
 #big img { max-width:96vw; max-height:92vh; object-fit:contain; }
 #big.on { display:flex; }
</style>
<header>
  <h1>{COUNT} photos</h1>
  <div id="pad">{HOLES}</div>
  <div id="out">
    <span id="left"></span>
    <button class="bar" id="copy">Copy photos.tsv</button>
  </div>
</header>
<main id="sheet">{CARDS}</main>
<div id="big"><img alt=""></div>
<dialog id="dlg">
  <p>Paste this over <code>photos.tsv</code>, then run
     <code>python3 tools/courses/import_photos.py &lt;course&gt; --sort</code>.</p>
  <textarea id="tsv" spellcheck="false"></textarea>
  <p><button class="bar" onclick="dlg.close()">Close</button></p>
</dialog>
<script>
const figs = [...document.querySelectorAll('figure')];
const pad = document.getElementById('pad');
const left = document.getElementById('left');
let cur = null;

// What you picked lives in the page until you copy it out, so a stray
// reload cannot cost you an afternoon of labelling.
const saved = JSON.parse(localStorage.getItem('holes') || '{}');
figs.forEach(f => {
  if (f.dataset.hole) saved[f.dataset.file] = f.dataset.hole;
  else if (saved[f.dataset.file]) f.dataset.hole = saved[f.dataset.file];
});
localStorage.setItem('holes', JSON.stringify(saved));

function paint() {
  let blank = 0;
  figs.forEach(f => {
    f.querySelector('b').textContent = f.dataset.hole || '';
    if (!f.dataset.hole) blank++;
  });
  left.textContent = blank ? blank + ' to go' : 'all labelled';
  [...pad.children].forEach(b =>
    b.classList.toggle('on', cur && b.dataset.h === cur.dataset.hole));
}

function select(f) {
  figs.forEach(o => o.classList.toggle('sel', o === f));
  cur = f;
  if (f) f.scrollIntoView({block: 'nearest'});
  paint();
}

function assign(h) {
  if (!cur) return;
  const from = figs.indexOf(cur);
  cur.dataset.hole = h;
  saved[cur.dataset.file] = h;
  localStorage.setItem('holes', JSON.stringify(saved));
  // Photos come in runs, so step to the next one: hold a hole number down
  // and you walk the round.
  select(figs[Math.min(from + 1, figs.length - 1)]);
}

figs.forEach(f => f.addEventListener('click', e => {
  if (e.shiftKey) { const b = document.getElementById('big');
    b.querySelector('img').src = f.querySelector('img').src; b.classList.add('on');
    return; }
  select(f);
}));
document.getElementById('big').addEventListener('click', e =>
  e.currentTarget.classList.remove('on'));
pad.addEventListener('click', e => { if (e.target.dataset.h) assign(e.target.dataset.h); });

// Type a hole number; everything else is one key too.
let typed = '';
addEventListener('keydown', e => {
  if (e.target.tagName === 'TEXTAREA') return;
  if (e.key >= '1' && e.key <= '9') {
    typed += e.key;
    const n = parseInt(typed, 10);
    // 1 could still become 19, so wait a beat before committing a bare 1.
    if (n >= 2 && n <= 19) { assign(String(n)); typed = ''; }
    else setTimeout(() => { if (typed === e.key) { assign(typed); typed = ''; } }, 400);
    return;
  }
  typed = '';
  if (e.key === 'a') assign('around');
  if (e.key === 'Backspace' && cur) { delete saved[cur.dataset.file];
    cur.dataset.hole = ''; localStorage.setItem('holes', JSON.stringify(saved)); paint(); }
  if (e.key === 'ArrowRight') select(figs[Math.min(figs.indexOf(cur) + 1, figs.length - 1)]);
  if (e.key === 'ArrowLeft') select(figs[Math.max(figs.indexOf(cur) - 1, 0)]);
  if (e.key === 'Escape') document.getElementById('big').classList.remove('on');
});

document.getElementById('copy').addEventListener('click', () => {
  const lines = ["# photo\\ttaken\\thole   (hole is 1-19, or 'around' for the shop,",
                 "#\\t\\tcar park, roads -- anything that is not one hole)"];
  figs.forEach(f => lines.push(
    [f.dataset.file, f.dataset.taken, f.dataset.hole].join('\\t')));
  const text = lines.join('\\n') + '\\n';
  navigator.clipboard.writeText(text).catch(() => {});
  document.getElementById('tsv').value = text;
  document.getElementById('dlg').showModal();
});

select(figs[0]);
</script>
"""


# --- import / sort ---------------------------------------------------------

def _folder(hole):
    return AROUND if hole == AROUND else "hole-%02d" % int(hole)


def find_photos(src, day):
    out = []
    for p in sorted(src.iterdir()):
        if not p.is_file() or p.suffix.lower() not in SUFFIXES:
            continue
        stamp = taken_at(p)
        if not stamp:
            continue
        if day and not stamp.startswith(day):
            continue
        out.append((p, stamp))
    out.sort(key=lambda t: t[1])
    return out


def do_import(root, src, day):
    shot = find_photos(src, day)
    if not shot:
        sys.exit("no photos taken on %s under %s" % (day or "any day", src))
    keep = root / "originals"
    keep.mkdir(parents=True, exist_ok=True)
    rows = rows_of(root / "photos.tsv")
    known = {r["file"] for r in rows}
    placed = {p.name: p.parent.name for p in root.glob("*/*.jpg")}
    added = 0
    for p, stamp in shot:
        name = "%s_%s.jpg" % (stamp[:10], re.sub(r"\D", "", p.stem)[-4:] or p.stem)
        if name in known:
            continue
        if not (keep / p.name).exists():
            shutil.copy2(p, keep / p.name)
        out = root / placed.get(name, "unsorted") / name
        out.parent.mkdir(parents=True, exist_ok=True)
        if not out.exists():
            subprocess.run(["sips", "-s", "format", "jpeg",
                            "-s", "formatOptions", str(JPEG_Q),
                            "-Z", str(JPEG_PX), str(p), "--out", str(out)],
                           check=True, capture_output=True)
        rows.append({"file": name, "taken": stamp, "hole": ""})
        added += 1
    rows.sort(key=lambda r: r["taken"])
    write_rows(root / "photos.tsv", rows)
    return rows, added


def do_sort(root):
    rows = rows_of(root / "photos.tsv")
    moved = 0
    for r in rows:
        if not r["hole"]:
            continue
        want = root / _folder(r["hole"])
        here = next((p for p in root.glob("*/" + r["file"])
                     if p.parent.name != "originals"), None)
        if here is None:
            print("  missing: %s" % r["file"])
            continue
        if here.parent == want:
            continue
        want.mkdir(parents=True, exist_ok=True)
        here.rename(want / r["file"])
        moved += 1
    for d in sorted(root.iterdir()):
        if d.is_dir() and d.name != "originals" and not any(d.iterdir()):
            d.rmdir()
    return rows, moved


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("course", help="course name, e.g. morley-field")
    ap.add_argument("src", nargs="?", help="folder the photos came off the phone into")
    ap.add_argument("--day", help="only photos taken on this date (YYYY-MM-DD)")
    ap.add_argument("--sort", action="store_true",
                    help="file already-imported photos by the hole in photos.tsv")
    ap.add_argument("--holes", type=int, default=19, help="holes on the course")
    a = ap.parse_args()

    repo = pathlib.Path(__file__).resolve().parent.parent.parent
    root = repo / "reference" / a.course
    root.mkdir(parents=True, exist_ok=True)
    (repo / "reference" / ".gdignore").touch()

    if a.sort:
        rows, moved = do_sort(root)
        print("sorted %d photo(s)" % moved)
    else:
        if not a.src:
            ap.error("give the folder to import from, or pass --sort")
        rows, added = do_import(root, pathlib.Path(a.src).expanduser(), a.day)
        print("imported %d new photo(s)" % added)

    write_sheet(root, rows, [str(h) for h in range(1, a.holes + 1)] + [AROUND])
    done = sum(1 for r in rows if r["hole"])
    print("%d photo(s), %d labelled -> %s" % (len(rows), done, root / "index.html"))


if __name__ == "__main__":
    main()
