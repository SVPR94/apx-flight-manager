#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-4.0
# Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
# Author: Savita Pawar (SVPR94)
# Created: 2026
"""Writes the apx_geo test fixtures and their expected values.

Everything here comes from independent implementations, so the Dart code is
checked against them rather than against itself:
  pyproj        projections (UTM, Web Mercator) and .prj WKT
  pyshp         Shapefile writing
  Pillow        TIFF writing (GeoTIFF tags added by hand, one file LZW)
  numpy         the four-corner homography
  eviltransform GCJ-02 / BD-09

Needs: pip install pyproj pyshp Pillow numpy eviltransform
Output: packages/apx_geo/test/fixtures/
"""
import json
import math
import os
import zipfile

import eviltransform
import numpy as np
import shapefile
from PIL import Image, TiffImagePlugin, TiffTags
from pyproj import CRS, Transformer
from pyproj.enums import WktVersion

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'packages', 'apx_geo', 'test', 'fixtures')
os.makedirs(OUT, exist_ok=True)
expected = {}

utm43 = CRS.from_epsg(32643)
to_utm43 = Transformer.from_crs(4326, 32643, always_xy=True)
from_utm43 = Transformer.from_crs(32643, 4326, always_xy=True)
from_merc = Transformer.from_crs(3857, 4326, always_xy=True)
to_merc = Transformer.from_crs(4326, 3857, always_xy=True)

RED = (255, 0, 0)
BLUE = (0, 0, 255)


def block(img, col, row, colour, r=1):
    """A (2r+1)² block centred on pixel (col, row)."""
    for y in range(row - r, row + r + 1):
        for x in range(col - r, col + r + 1):
            img.putpixel((x, y), colour)


def geotiff(path, img, keys, tie=None, scale=None, transform=None, citation=None, nodata=None, compression=None):
    ifd = TiffImagePlugin.ImageFileDirectory_v2()
    if tie is not None:
        ifd[33922] = tuple(float(v) for v in tie)
        ifd.tagtype[33922] = TiffTags.DOUBLE
    if scale is not None:
        ifd[33550] = tuple(float(v) for v in scale)
        ifd.tagtype[33550] = TiffTags.DOUBLE
    if transform is not None:
        ifd[34264] = tuple(float(v) for v in transform)
        ifd.tagtype[34264] = TiffTags.DOUBLE
    directory = [1, 1, 0, len(keys)]
    for k, v in keys:
        directory += [k, 0, 1, v]
    ifd[34735] = tuple(directory)
    ifd.tagtype[34735] = TiffTags.SHORT
    if citation:
        ifd[34737] = citation + '|'
        ifd.tagtype[34737] = TiffTags.ASCII
    if nodata is not None:
        ifd[42113] = str(nodata)
        ifd.tagtype[42113] = TiffTags.ASCII
    img.save(os.path.join(OUT, path), tiffinfo=ifd, compression=compression)


def centre_of(col, row):
    """Continuous pixel-corner coordinates of pixel (col,row)'s centre."""
    return col + 0.5, row + 0.5


# 1. UTM 43N, tiepoint + pixel scale, PixelIsArea, uncompressed RGB (near Pune).
ox, oy = to_utm43.transform(73.85, 18.52)
ox, oy = round(ox, 2), round(oy, 2)
img = Image.new('RGB', (400, 300), (128, 128, 128))
block(img, 250, 120, RED)
block(img, 60, 240, BLUE)
geotiff('utm43n.tif', img, [(1024, 1), (1025, 1), (3072, 32643)], tie=(0, 0, 0, ox, oy, 0), scale=(0.25, 0.25, 0))
pts = {}
for name, (c, r) in {'red': (250, 120), 'blue': (60, 240)}.items():
    cx, cy = centre_of(c, r)
    lon, lat = from_utm43.transform(ox + cx * 0.25, oy - cy * 0.25)
    pts[name] = [lat, lon]
expected['utm43n.tif'] = {'markers': pts, 'width': 400, 'height': 300}

# 2. Geographic WGS-84, PixelIsPoint (tiepoint at the first pixel's centre), Zurich.
lon0, lat0, d = 8.54, 47.37, 0.0000035
img = Image.new('RGB', (300, 200), (90, 160, 90))
block(img, 100, 80, RED)
geotiff('wgs84_point.tif', img, [(1024, 2), (1025, 2), (2048, 4326)], tie=(0, 0, 0, lon0, lat0, 0), scale=(d, d, 0))
# PixelIsPoint: pixel (c, r) centre is exactly at lon0 + c*d, lat0 - r*d.
expected['wgs84_point.tif'] = {'markers': {'red': [lat0 - 80 * d, lon0 + 100 * d]}}

# 3. Web Mercator with a rotated ModelTransformation, LZW compressed (Sydney).
mx, my = to_merc.transform(151.2, -33.86)
s, a = 0.3, math.radians(20)
# x = A*col + B*row + D ; y = E*col + F*row + H   (pixel corners)
A, B = s * math.cos(a), s * math.sin(a)
E, F = s * math.sin(a), -s * math.cos(a)
img = Image.new('RGB', (256, 256), (200, 190, 150))
block(img, 180, 60, RED)
geotiff('merc_rotated.tif', img, [(1024, 1), (1025, 1), (3072, 3857)],
        transform=(A, B, 0, mx, E, F, 0, my, 0, 0, 0, 0, 0, 0, 0, 1), compression='tiff_lzw')
cx, cy = centre_of(180, 60)
lon, lat = from_merc.transform(mx + A * cx + B * cy, my + E * cx + F * cy)
expected['merc_rotated.tif'] = {'markers': {'red': [lat, lon]}}

# 4. 16-bit single-band elevation model with nodata = 0 (needs stretching).
dem = np.zeros((64, 64), dtype=np.uint16)
for y in range(64):
    for x in range(64):
        dem[y, x] = 0 if x < 8 else 500 + 20 * x + 5 * y
Image.fromarray(dem).save(os.path.join(OUT, 'tmp_dem.tif'))
img = Image.open(os.path.join(OUT, 'tmp_dem.tif'))
geotiff('dem16.tif', img, [(1024, 2), (1025, 1), (2048, 4326)], tie=(0, 0, 0, 10.0, 46.0, 0), scale=(0.0001, 0.0001, 0), nodata=0)
os.remove(os.path.join(OUT, 'tmp_dem.tif'))
expected['dem16.tif'] = {'nodataColumns': 8, 'width': 64, 'height': 64}

# 5. PNG placed by four corners (a perspective quadrilateral, Pune).
w, h = 300, 200
img = Image.new('RGBA', (w, h), (240, 240, 240, 255))
block(img, 210, 50, RED + (255,))
img.save(os.path.join(OUT, 'photo.png'))
corners = [(18.5300, 73.8500), (18.5302, 73.8530), (18.5275, 73.8528), (18.5277, 73.8497)]  # TL TR BR BL
ground = [to_merc.transform(lon, lat) for lat, lon in corners]
o = ground[0]
src = [(gx - o[0], gy - o[1]) for gx, gy in ground]
dst = [(0, 0), (w, 0), (w, h), (0, h)]
M = []
rhs = []
for (x, y), (u, v) in zip(dst, src):  # solve pixel -> ground
    M.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); rhs.append(u)
    M.append([0, 0, 0, x, y, 1, -v * x, -v * y]); rhs.append(v)
hh = np.linalg.solve(np.array(M), np.array(rhs))
H = np.append(hh, 1).reshape(3, 3)
p = H @ np.array([210.5, 50.5, 1.0])
lon, lat = from_merc.transform(p[0] / p[2] + o[0], p[1] / p[2] + o[1])
expected['photo.png'] = {'corners': corners, 'markers': {'red': [lat, lon]}}

# 6. JPEG-free world file case: PNG + .pgw (rotated) + ESRI .prj in UTM 43N.
img = Image.new('RGB', (200, 160), (220, 220, 200))
block(img, 40, 130, RED)
img.save(os.path.join(OUT, 'ortho.png'))
wx, wy = to_utm43.transform(73.86, 18.53)
A, D, Bw, Ew = 0.5, -0.05, -0.05, -0.5  # world file order: A D B E C F (pixel centres)
with open(os.path.join(OUT, 'ortho.pgw'), 'w') as f:
    f.write('\n'.join(str(v) for v in [A, D, Bw, Ew, wx, wy]) + '\n')
with open(os.path.join(OUT, 'ortho.prj'), 'w') as f:
    f.write(utm43.to_wkt(WktVersion.WKT1_ESRI))
lon, lat = from_utm43.transform(A * 40 + Bw * 130 + wx, D * 40 + Ew * 130 + wy)
expected['ortho.png'] = {'markers': {'red': [lat, lon]}}

# 6b. GDAL/QGIS-style PNG with a .aux.xml sidecar (GeoTransform + SRS WKT), UTM 43N.
img = Image.new('RGB', (180, 120), (210, 220, 230))
block(img, 150, 20, RED)
img.save(os.path.join(OUT, 'export.png'))
gx, gy = to_utm43.transform(73.855, 18.525)
gt = [gx, 0.4, 0.1, gy, 0.1, -0.4]  # GDAL order: x0, dx, rot, y0, rot, dy (pixel corners)
srs = utm43.to_wkt(WktVersion.WKT1_GDAL).replace('"', '&quot;')
with open(os.path.join(OUT, 'export.png.aux.xml'), 'w') as f:
    f.write('<PAMDataset>\n  <SRS dataAxisToSRSAxisMapping="1,2">' + srs + '</SRS>\n'
            '  <GeoTransform> ' + ', '.join(f'{v:.10e}' for v in gt) + '</GeoTransform>\n</PAMDataset>\n')
cx, cy = centre_of(150, 20)
lon, lat = from_utm43.transform(gt[0] + gt[1] * cx + gt[2] * cy, gt[3] + gt[4] * cx + gt[5] * cy)
expected['export.png'] = {'markers': {'red': [lat, lon]}}

# 7. Shapefiles.
esri_prj = utm43.to_wkt(WktVersion.WKT1_ESRI)
bx, by = to_utm43.transform(73.85, 18.52)
outer = [(bx, by), (bx, by + 100), (bx + 120, by + 100), (bx + 120, by), (bx, by)]          # clockwise
hole = [(bx + 30, by + 30), (bx + 60, by + 30), (bx + 60, by + 60), (bx + 30, by + 60), (bx + 30, by + 30)]  # ccw
second = [(bx + 200, by), (bx + 200, by + 50), (bx + 260, by + 50), (bx + 260, by), (bx + 200, by)]
w = shapefile.Writer(os.path.join(OUT, 'fields_utm'), shapeType=shapefile.POLYGON, encoding='utf-8')
w.field('NAME', 'C', 40)
w.field('AREA_HA', 'N', 10, 3)
w.field('SPRAYED', 'L')
w.field('DATE', 'D')
w.poly([outer, hole]); w.record('Café field 田', 1.11, True, '20260315')
w.poly([second]); w.record('North', 0.3, False, '20260401')
w.close()
with open(os.path.join(OUT, 'fields_utm.prj'), 'w') as f:
    f.write(esri_prj)
with open(os.path.join(OUT, 'fields_utm.cpg'), 'w') as f:
    f.write('UTF-8')
geo = lambda ring: [list(reversed(from_utm43.transform(x, y))) for x, y in ring]  # [lat, lon]
expected['fields_utm.shp'] = {
    'features': 2,
    'outer0': geo(outer), 'hole0': geo(hole), 'outer1': geo(second),
    'attributes0': {'NAME': 'Café field 田', 'AREA_HA': 1.11, 'SPRAYED': True, 'DATE': '2026-03-15'},
}
with zipfile.ZipFile(os.path.join(OUT, 'fields_utm.zip'), 'w') as z:
    for ext in ('shp', 'shx', 'dbf', 'prj', 'cpg'):
        z.write(os.path.join(OUT, f'fields_utm.{ext}'), f'data/fields_utm.{ext}')

w = shapefile.Writer(os.path.join(OUT, 'track_z'), shapeType=shapefile.POLYLINEZ)
w.field('ID', 'N', 5, 0)
track = [(73.85, 18.52, 10), (73.851, 18.521, 12), (73.852, 18.5205, 15)]
w.linez([track]); w.record(7)
w.close()
expected['track_z.shp'] = {'line': [[lat, lon] for lon, lat, _ in track]}

w = shapefile.Writer(os.path.join(OUT, 'points'), shapeType=shapefile.POINT)
w.field('LABEL', 'C', 10)
w.point(73.85, 18.52); w.record('A')
w.null(); w.record('gap')
w.point(73.86, 18.53); w.record('B')
w.close()
expected['points.shp'] = {'points': [[18.52, 73.85], [18.53, 73.86]], 'skipped': 1}

# 8. China datums.
china = []
for lat, lon in [(39.9087, 116.3975), (31.2304, 121.4737), (22.5431, 114.0579), (30.5728, 104.0668)]:
    g = eviltransform.wgs2gcj(lat, lon)
    b = eviltransform.gcj2bd(*g)
    china.append({'wgs': [lat, lon], 'gcj': list(g), 'bd': list(b)})
expected['china'] = china

with open(os.path.join(OUT, 'expected.json'), 'w') as f:
    json.dump(expected, f, indent=1, ensure_ascii=False)
print('wrote', sorted(os.listdir(OUT)))
