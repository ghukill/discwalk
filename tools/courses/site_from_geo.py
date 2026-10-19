# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow", "pyproj", "tifffile"]
# ///
"""Fetch a real place's ground for a discwalk course: a 16-bit heightmap from
USGS 3DEP lidar elevation, and an aerial photo (USDA NAIP) to trace from.

    uv run tools/courses/site_from_geo.py --ul 42.215551,-83.565320 \\
        --lr 42.210182,-83.557825 --out data/courses/ponds-at-lakeshore

Writes into --out:
    height.png    16-bit grayscale, 1 px per metre, north up (see
                  docs/COURSE_FORMAT.md); black = height_min, white = height_max
    aerial.png    NAIP photo of the same box, 2 px per metre, north up
    site.json     the numbers to copy into course.json: size, height range, geo

The course frame: x runs east and z runs south, in metres, from the upper-left
(north-west) corner. Over a few hundred metres web mercator is as good as flat,
so the frame is just mercator scaled by cos(latitude): north-up, square pixels,
and it lines up with map screenshots (which are mercator too).

Both services are US-only and public domain. 3DEP is bare earth (buildings
and trees removed), mostly 1 m lidar; elsewhere it falls back to coarser data.
"""
import argparse
import json
import math
import pathlib
import time
import urllib.error
import urllib.request

import numpy as np
import tifffile
from PIL import Image
from pyproj import Transformer

DEM_URL = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage"
NAIP_URL = "https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer/exportImage"
MARGIN = 20.0          # m of extra DEM around the box, so edge samples interpolate


def latlon(s):
    a, b = (float(v) for v in s.split(","))
    return a, b


def export(url, params, path):
    q = "&".join(f"{k}={v}" for k, v in params.items())
    for attempt in range(4):      # these services time out now and then
        try:
            with urllib.request.urlopen(f"{url}?{q}&f=json", timeout=120) as r:
                j = json.load(r)
            break
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  {url.split('/')[-3]}: {e}, retrying")
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit(f"{url}: gave up")
    if "href" not in j:
        raise SystemExit(f"{url}: {j}")
    urllib.request.urlretrieve(j["href"], path)
    return j


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ul", required=True, type=latlon, help="upper-left lat,lon")
    ap.add_argument("--lr", required=True, type=latlon, help="lower-right lat,lon")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)

    (lat0, lon0), (lat1, lon1) = a.ul, a.lr
    merc = Transformer.from_crs(4326, 3857, always_xy=True)
    X0, Y0 = merc.transform(lon0, lat0)
    X1, Y1 = merc.transform(lon1, lat1)
    k = math.cos(math.radians((lat0 + lat1) / 2))
    W = int(round((X1 - X0) * k))
    H = int(round((Y0 - Y1) * k))
    print(f"course frame: {W} x {H} m")

    # Course pixel centres -> lon/lat -> UTM, then sample a UTM DEM there.
    zone = int((lon0 + 180) // 6) + 1
    epsg = 32600 + zone
    to_ll = Transformer.from_crs(3857, 4326, always_xy=True)
    to_utm = Transformer.from_crs(4326, epsg, always_xy=True)
    xs = (np.arange(W) + 0.5) / k + X0
    ys = Y0 - (np.arange(H) + 0.5) / k
    gx, gy = np.meshgrid(xs, ys)
    lon, lat = to_ll.transform(gx, gy)
    ux, uy = to_utm.transform(lon, lat)
    ux0, ux1 = ux.min() - MARGIN, ux.max() + MARGIN
    uy0, uy1 = uy.min() - MARGIN, uy.max() + MARGIN
    dw, dh = int(math.ceil(ux1 - ux0)), int(math.ceil(uy1 - uy0))
    tif = a.out / "_dem.tif"
    export(DEM_URL, {"bbox": f"{ux0},{uy0},{ux0 + dw},{uy0 + dh}", "bboxSR": epsg, "imageSR": epsg,
                     "size": f"{dw},{dh}", "format": "tiff", "pixelType": "F32",
                     "interpolation": "RSP_BilinearInterpolation"}, tif)
    dem = tifffile.imread(tif).astype(np.float64)
    tif.unlink()
    # Bilinear lookup: DEM row 0 is the north edge, pixel centres at +0.5.
    fx = np.clip(ux - ux0 - 0.5, 0, dw - 1.001)
    fy = np.clip(uy0 + dh - uy - 0.5, 0, dh - 1.001)
    ix, iy = fx.astype(int), fy.astype(int)
    tx, ty = fx - ix, fy - iy
    h = (dem[iy, ix] * (1 - tx) * (1 - ty) + dem[iy, ix + 1] * tx * (1 - ty)
         + dem[iy + 1, ix] * (1 - tx) * ty + dem[iy + 1, ix + 1] * tx * ty)
    lo, hi = float(np.floor(h.min() * 10) / 10), float(np.ceil(h.max() * 10) / 10)
    img = np.round((h - lo) / (hi - lo) * 65535).astype(np.uint16)
    Image.fromarray(img).save(a.out / "height.png")
    print(f"height.png: {W} x {H}, {lo} .. {hi} m")

    export(NAIP_URL, {"bbox": f"{X0},{Y1},{X1},{Y0}", "bboxSR": 3857, "imageSR": 3857,
                      "size": f"{W * 2},{H * 2}", "format": "png"}, a.out / "aerial.png")
    Image.open(a.out / "aerial.png").convert("RGB").save(a.out / "aerial.png")
    print("aerial.png: NAIP, 2 px/m")

    site = {"size": [W, H], "height_min": lo, "height_max": hi,
            "geo": {"upper_left": [lat0, lon0], "lower_right": [lat1, lon1]},
            "sources": {"height": "USGS 3DEP (public domain)", "aerial": "USDA NAIP via USGS (public domain)"}}
    (a.out / "site.json").write_text(json.dumps(site, indent=1) + "\n")


if __name__ == "__main__":
    main()
