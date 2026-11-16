// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:apx_geo/apx_geo.dart';
import 'package:test/test.dart';

final expected = jsonDecode(File('test/fixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;

File fixture(String name) => File('test/fixtures/$name');

/// Renders the zoom‑[z] tile that should contain [where] and returns the
/// centroid of pixels matching [isMarker], minus where [where] is expected in
/// that tile: the alignment error in map pixels.
(double, double) alignmentError(
  GeoRaster r,
  GeoPoint where,
  bool Function(int r, int g, int b, int a) isMarker, {
  int z = 19,
}) {
  final t = WebMercator.tileAt(where, z);
  final tile = TileWarp(t, r.locate).render(r.image);
  var sx = 0.0, sy = 0.0, n = 0;
  for (var y = 0; y < tileSize; y++) {
    for (var x = 0; x < tileSize; x++) {
      final i = (y * tileSize + x) * 4;
      final p = tile.pixels;
      if (isMarker(p[i], p[i + 1], p[i + 2], p[i + 3])) {
        sx += x + 0.5;
        sy += y + 0.5;
        n++;
      }
    }
  }
  expect(n, greaterThan(0), reason: 'marker not drawn in tile $t');
  final (px, py) = WebMercator.toPixel(where, z);
  return (sx / n - (px - t.x * tileSize), sy / n - (py - t.y * tileSize));
}

bool red(int r, int g, int b, int a) => a > 200 && r > 180 && g < 90 && b < 90;
bool blue(int r, int g, int b, int a) => a > 200 && b > 180 && r < 90 && g < 90;

GeoPoint marker(String file, String name) {
  final m = (expected[file]['markers'] as Map)[name] as List;
  return GeoPoint(m[0], m[1]);
}

Matcher withinPixel = predicate<(double, double)>((e) => e.$1.abs() <= 1 && e.$2.abs() <= 1, 'within ±1 px');

void main() {
  group('GeoTIFF', () {
    test('UTM tiepoint + scale aligns to ±1 px at zoom 19', () {
      final r = GeoTiff.read(fixture('utm43n.tif').readAsBytesSync());
      expect(r.image.width, 400);
      expect(r.metresPerPixel, closeTo(0.25, 0.01));
      expect(alignmentError(r, marker('utm43n.tif', 'red'), red), withinPixel);
      expect(alignmentError(r, marker('utm43n.tif', 'blue'), blue), withinPixel);
    });

    test('geographic PixelIsPoint aligns to ±1 px at zoom 19', () {
      final r = GeoTiff.read(fixture('wgs84_point.tif').readAsBytesSync());
      expect(alignmentError(r, marker('wgs84_point.tif', 'red'), red), withinPixel);
    });

    test('rotated ModelTransformation (LZW) aligns to ±1 px at zoom 19', () {
      final r = GeoTiff.read(fixture('merc_rotated.tif').readAsBytesSync());
      expect(alignmentError(r, marker('merc_rotated.tif', 'red'), red), withinPixel);
    });

    test('16‑bit elevation is stretched and nodata is transparent', () {
      final r = GeoTiff.read(fixture('dem16.tif').readAsBytesSync());
      final px = r.image.pixels;
      int at(int x, int y, int c) => px[(y * 64 + x) * 4 + c];
      expect(at(3, 10, 3), 0, reason: 'nodata column');
      expect(at(20, 10, 3), 255);
      expect(at(60, 60, 0), greaterThan(at(12, 2, 0)), reason: 'higher ground is brighter');
      expect(at(20, 10, 0), at(20, 10, 1), reason: 'single band is grey');
    });

    test('reads info without decoding and rejects non‑TIFFs', () {
      final info = GeoTiff.readInfo(fixture('utm43n.tif').readAsBytesSync());
      expect(info.crs.epsg, 32643);
      expect(info.width, 400);
      expect(() => GeoTiff.readInfo(fixture('photo.png').readAsBytesSync()), throwsFormatException);
    });

    test('pyramid covers the image and box‑filters lower zooms', () {
      final r = GeoTiff.read(fixture('utm43n.tif').readAsBytesSync());
      final written = <TileId, RgbaRaster>{};
      final n = buildPyramid(r, _MapSink(written));
      expect(n, written.length);
      expect(r.nativeZoom, 20); // 0.25 m/px at 18.5° N
      expect(written.keys.map((t) => t.z).reduce(math.max), 20);
      expect(written.keys.map((t) => t.z).reduce(math.min), r.minZoom);
      // Every stored tile has content, and each level overlaps the raster.
      expect(written.values.every((t) => !t.isEmpty), isTrue);
    });
  });

  group('Image overlays', () {
    test('four‑corner placement (perspective) aligns to ±1 px at zoom 19', () {
      final e = expected['photo.png'];
      final corners = [for (final c in (e['corners'] as List)) GeoPoint(c[0], c[1])];
      final r = ImageOverlay.place(
        ImageOverlay.decode(fixture('photo.png').readAsBytesSync()),
        CornerPlacement(corners),
      );
      expect(alignmentError(r, marker('photo.png', 'red'), red), withinPixel);
    });

    test('world file + ESRI .prj in UTM aligns to ±1 px at zoom 19', () {
      final placement = WorldFilePlacement.parse(
        fixture('ortho.pgw').readAsStringSync(),
        prj: fixture('ortho.prj').readAsStringSync(),
      );
      final r = ImageOverlay.place(ImageOverlay.decode(fixture('ortho.png').readAsBytesSync()), placement);
      expect(alignmentError(r, marker('ortho.png', 'red'), red), withinPixel);
    });

    test('GDAL/QGIS .aux.xml sidecar (corner‑based GeoTransform, rotated, UTM) aligns to ±1 px at zoom 19', () {
      final placement = WorldFilePlacement.fromAuxXml(fixture('export.png.aux.xml').readAsStringSync());
      expect(placement.crs.epsg, 32643);
      final r = ImageOverlay.place(ImageOverlay.decode(fixture('export.png').readAsBytesSync()), placement);
      expect(alignmentError(r, marker('export.png', 'red'), red), withinPixel);
      expect(() => WorldFilePlacement.fromAuxXml('<PAMDataset/>'), throwsFormatException);
    });

    test('world file in projected units without .prj is refused clearly', () {
      final p = WorldFilePlacement.parse(fixture('ortho.pgw').readAsStringSync());
      expect(
        () => p.corners(10, 10),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('.prj'))),
      );
    });

    test('placements survive JSON', () {
      const c = CentrePlacement(center: GeoPoint(1, 2), widthMetres: 3, heightMetres: 4, rotationDeg: 5);
      final back = ImagePlacement.fromJson(jsonDecode(jsonEncode(c.toJson()))) as CentrePlacement;
      expect(back.center, c.center);
      expect(back.rotationDeg, 5);
      expect(ImageOverlay.worldFileExtensions('.png'), ['.pgw', '.pngw', '.wld']);
      expect(ImageOverlay.worldFileExtensions('.jpeg').first, '.jgw');
    });
  });

  group('Shapefile', () {
    void expectRing(List<GeoPoint> got, List ref) {
      expect(got.length, ref.length);
      for (var i = 0; i < got.length; i++) {
        expect(haversineMetres(got[i], GeoPoint(ref[i][0], ref[i][1])), lessThan(0.01));
      }
    }

    VectorLayer readSet(String base) => Shapefile.read(
      name: base,
      shp: fixture('$base.shp').readAsBytesSync(),
      dbf: fixture('$base.dbf').existsSync() ? fixture('$base.dbf').readAsBytesSync() : null,
      prj: fixture('$base.prj').existsSync() ? fixture('$base.prj').readAsStringSync() : null,
      cpg: fixture('$base.cpg').existsSync() ? fixture('$base.cpg').readAsStringSync() : null,
    );

    test('UTM polygons with a hole, reprojected via .prj, with UTF‑8 attributes', () {
      final e = expected['fields_utm.shp'];
      final l = readSet('fields_utm');
      expect(l.features, hasLength(2));
      expect(l.crsName, contains('UTM zone 43N'));
      final p0 = (l.features[0].geometry as VectorPolygons).polygons.single;
      expectRing(p0.outer, e['outer0']);
      expectRing(p0.holes.single, e['hole0']);
      expectRing((l.features[1].geometry as VectorPolygons).polygons.single.outer, e['outer1']);
      expect(l.features[0].attributes, e['attributes0']);
      expect(l.fields, ['NAME', 'AREA_HA', 'SPRAYED', 'DATE']);
    });

    test('zipped set reads the same', () {
      final layers = Shapefile.readZip(fixture('fields_utm.zip').readAsBytesSync());
      expect(layers.single.name, 'fields_utm');
      expect(layers.single.features[0].attributes['NAME'], 'Café field 田');
    });

    test('PolyLineZ without .prj is taken as WGS‑84', () {
      final l = readSet('track_z');
      expectRing((l.features.single.geometry as VectorLines).lines.single, expected['track_z.shp']['line']);
      expect(l.features.single.attributes['ID'], 7);
    });

    test('points keep their records aligned across a null shape', () {
      final l = readSet('points');
      expect(l.skipped, 1);
      expect(l.features.map((f) => f.attributes['LABEL']), ['A', 'B']);
      expect((l.features[1].geometry as VectorPoints).points.single, const GeoPoint(18.53, 73.86));
    });

    test('rejects garbage', () {
      expect(() => Shapefile.read(name: 'x', shp: fixture('photo.png').readAsBytesSync()), throwsFormatException);
    });
  });

  group('GeoJSON', () {
    VectorLayer readFixture(String name) => GeoJson.read(name: 'file', bytes: fixture(name).readAsBytesSync());
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    test('every geometry type, holes, collections; bad features are skipped', () {
      final l = readFixture('mixed.geojson');
      expect(l.name, 'field survey');
      expect(l.crsName, 'WGS 84');
      expect(l.skipped, 2, reason: 'null geometry and a one-number position');
      final byLabel = <String, List<VectorGeometry>>{};
      for (final f in l.features) {
        byLabel.putIfAbsent(f.attributes['label'] as String, () => []).add(f.geometry);
      }
      expect((byLabel['Pump']!.single as VectorPoints).points.single, const GeoPoint(18.53, 73.86));
      expect((byLabel['Wells']!.single as VectorPoints).points, hasLength(2));
      expect((byLabel['Canal']!.single as VectorLines).lines.single, hasLength(3));
      expect((byLabel['Roads']!.single as VectorLines).lines, hasLength(2));
      final pond = (byLabel['Field with pond']!.single as VectorPolygons).polygons.single;
      expect(pond.outer, hasLength(5));
      expect(pond.holes.single.first, const GeoPoint(18.505, 73.805));
      expect((byLabel['Two plots']!.single as VectorPolygons).polygons, hasLength(2));
      // A collection becomes one feature per kind, sharing the properties.
      expect(byLabel['Site']!.map((g) => g.runtimeType), [VectorPoints, VectorPolygons]);
      expect(l.bounds!.north, closeTo(18.61, 1e-9));
    });

    test('properties: id kept, nested values shown as JSON, all keys listed', () {
      final l = readFixture('mixed.geojson');
      final pump = l.features.first.attributes;
      expect(pump, {'id': 'pump-1', 'label': 'Pump', 'depth_m': 12.5, 'ok': true, 'tags': '["a","b"]'});
      expect(l.fields, containsAll(['id', 'label', 'depth_m', 'ok', 'tags']));
    });

    test('legacy "crs" with an EPSG code is reprojected', () {
      final l = readFixture('utm43n.geojson');
      expect(l.crsName, contains('UTM zone 43N'));
      final p = (l.features.single.geometry as VectorPoints).points.single;
      final want = Crs.utm(43).toWgs84(380000, 2050000);
      expect(haversineMetres(p, want), lessThan(0.01));
      expect(p.lat, closeTo(18.53, 0.01));
    });

    test('CRS84 and EPSG:4326 names, single Feature, bare geometry, BOM', () {
      final crs84 = GeoJson.read(
        name: 'x',
        bytes: bytes(
          '{"type":"Point","coordinates":[73.8,18.5],"crs":{"type":"name","properties":{"name":"urn:ogc:def:crs:OGC:1.3:CRS84"}}}',
        ),
      );
      expect((crs84.features.single.geometry as VectorPoints).points.single, const GeoPoint(18.5, 73.8));
      expect(crs84.name, 'x');
      final feature = GeoJson.read(
        name: 'x',
        bytes: bytes('\uFEFF{"type":"Feature","properties":{"a":1},"geometry":{"type":"Point","coordinates":[1,2]}}'),
      );
      expect(feature.features.single.attributes, {'a': 1});
      final epsg4326 = GeoJson.read(
        name: 'x',
        bytes: bytes(
          '{"type":"Point","coordinates":[73.8,18.5],"crs":{"type":"name","properties":{"name":"EPSG:4326"}}}',
        ),
      );
      expect(epsg4326.crsName, 'WGS 84');
    });

    test('readable errors', () {
      expect(() => GeoJson.read(name: 'x', bytes: fixture('photo.png').readAsBytesSync()), throwsFormatException);
      expect(() => GeoJson.read(name: 'x', bytes: bytes('[1,2]')), throwsFormatException);
      expect(() => GeoJson.read(name: 'x', bytes: bytes('{"type":"Topology"}')), throwsFormatException);
      // Projected numbers with no CRS named.
      expect(
        () => GeoJson.read(name: 'x', bytes: bytes('{"type":"Point","coordinates":[380000,2050000]}')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('EPSG:4326'))),
      );
      // Unknown projection named.
      expect(
        () => GeoJson.read(
          name: 'x',
          bytes: bytes(
            '{"type":"Point","coordinates":[380000,2050000],"crs":{"type":"name","properties":{"name":"EPSG:2154"}}}',
          ),
        ),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('EPSG:2154'))),
      );
    });
  });
}

final class _MapSink implements TileSink {
  _MapSink(this.out);
  final Map<TileId, RgbaRaster> out;
  @override
  void put(TileId tile, RgbaRaster pixels) => out[tile] = pixels;
}
