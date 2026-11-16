// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';

import 'package:apx_geo/apx_geo.dart';
import 'package:test/test.dart';

final expected = jsonDecode(File('test/fixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('Web Mercator', () {
    test('tile maths matches the slippy‑map definition', () {
      expect(WebMercator.tileAt(const GeoPoint(51.5074, -0.1278), 10), const TileId(10, 511, 340));
      expect(WebMercator.tileAt(const GeoPoint(-33.8688, 151.2093), 12), const TileId(12, 3768, 2457));
      final b = const TileId(1, 0, 0).bounds;
      expect(b.west, -180);
      expect(b.east, closeTo(0, 1e-12));
      expect(b.north, closeTo(WebMercator.maxLatitude, 1e-9));
      expect(b.south, closeTo(0, 1e-9));
    });

    test('metres round trip and quadkeys', () {
      final (x, y) = WebMercator.toMetres(18.52, 73.85);
      final p = WebMercator.fromMetres(x, y);
      expect(p.lat, closeTo(18.52, 1e-10));
      expect(p.lon, closeTo(73.85, 1e-10));
      expect(const TileId(3, 3, 5).quadKey, '213'); // Bing's documented example
    });

    test('counts and lists covering tiles', () {
      const b = GeoBounds(18.5, 73.8, 18.6, 73.9);
      for (var z = 10; z <= 14; z++) {
        expect(WebMercator.tilesCovering(b, z).length, WebMercator.countTiles(b, z, z));
      }
    });
  });

  group('China datums', () {
    for (final c in (expected['china'] as List).cast<Map<String, dynamic>>()) {
      final wgs = GeoPoint(c['wgs'][0], c['wgs'][1]);
      test('matches eviltransform at $wgs', () {
        // eviltransform uses the WGS‑84 radius (6378137) where the original
        // algorithm uses Krasovsky's 6378245; the two differ by about a centimetre.
        final gcj = wgs84ToGcj02(wgs);
        expect(haversineMetres(gcj, GeoPoint(c['gcj'][0], c['gcj'][1])), lessThan(0.02));
        final bd = gcj02ToBd09(gcj);
        expect(haversineMetres(bd, GeoPoint(c['bd'][0], c['bd'][1])), lessThan(0.02));
        // The BD‑09 step itself is identical.
        final bdRef = gcj02ToBd09(GeoPoint(c['gcj'][0], c['gcj'][1]));
        expect(bdRef.lat, closeTo(c['bd'][0], 1e-12));
        expect(bdRef.lon, closeTo(c['bd'][1], 1e-12));
        // Inverses back to WGS‑84 within a millimetre.
        final back = toWgs84From(MapDatum.bd09, bd);
        expect(haversineMetres(back, wgs), lessThan(0.001));
      });
    }

    test('no offset outside the GCJ‑02 box', () {
      const london = GeoPoint(51.5, -0.12);
      expect(wgs84To(MapDatum.gcj02, london), london);
      // The conventional box is coarse: western India is inside it.
      expect(outOfChina(const GeoPoint(18.52, 73.85)), isFalse);
    });

    test('Baidu Mercator matches Baidu\'s own JS (and its documented sample)', () {
      // Reference values: a Python port that reads the coefficient arrays
      // straight from api.map.baidu.com getscript v3.0.
      const ref = [
        (39.915, 116.404, 12958175.000248697, 4825923.766034241),
        (31.2397, 121.4998, 13525443.033606865, 3641554.4936149283),
        (22.5, 114.06, 12697239.276355423, 2555164.3970601954),
        (-33.86, 151.2, 16831690.14776838, -3985991.7813541875),
        (64.1, -21.9, -2437923.3756430177, 9336401.567374706),
      ];
      for (final (lat, lon, x, y) in ref) {
        final (mx, my) = BaiduMercator.fromBd09(GeoPoint(lat, lon));
        expect(mx, closeTo(x, 1e-4));
        expect(my, closeTo(y, 1e-4));
        // Baidu's inverse polynomial is itself approximate (≈1 m at 64° N, the
        // same in the reference); tiles only use the forward direction.
        final back = BaiduMercator.toBd09(mx, my);
        expect(back.lat, closeTo(lat, 2e-5));
        expect(back.lon, closeTo(lon, 2e-5));
      }
    });
  });

  group('Homography', () {
    test('maps the four points exactly and inverts', () {
      final from = [(0.0, 0.0), (300.0, 0.0), (300.0, 200.0), (0.0, 200.0)];
      final to = [(10.0, 5.0), (320.0, 30.0), (290.0, 260.0), (-20.0, 210.0)];
      final h = Homography.fromPoints(from, to);
      for (var i = 0; i < 4; i++) {
        final (u, v) = h.apply(from[i].$1, from[i].$2);
        expect(u, closeTo(to[i].$1, 1e-9));
        expect(v, closeTo(to[i].$2, 1e-9));
      }
      final inv = h.inverse();
      final (x, y) = inv.apply(150, 120);
      final (u, v) = h.apply(x, y);
      expect(u, closeTo(150, 1e-9));
      expect(v, closeTo(120, 1e-9));
    });

    test('rejects degenerate corners', () {
      expect(
        () => Homography.fromPoints([(0, 0), (1, 1), (2, 2), (0, 1)], [(0, 0), (1, 0), (1, 1), (0, 1)]),
        throwsArgumentError,
      );
    });
  });

  group('CRS', () {
    test('UTM agrees with pyproj', () {
      // The fixture tiepoint is pyproj's UTM 43N for (18.52 N, 73.85 E), rounded to cm.
      final p = Crs.fromEpsg(32643)!.toWgs84(378613.25, 2048104.86);
      expect(haversineMetres(p, const GeoPoint(18.52, 73.85)), lessThan(0.02));
    });

    test('parses ESRI WKT from a .prj', () {
      final crs = Crs.parse(File('test/fixtures/fields_utm.prj').readAsStringSync());
      expect(crs.name, contains('UTM zone 43N'));
      expect(
        Crs.parse(
          'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137,298.257223563]],'
          'PRIMEM["Greenwich",0],UNIT["Degree",0.0174532925199433]]',
        ).isGeographic,
        isTrue,
      );
    });

    test('centre placement puts corners at the right distance', () {
      const c = GeoPoint(18.52, 73.85);
      final corners = const CentrePlacement(
        center: c,
        widthMetres: 120,
        heightMetres: 80,
        rotationDeg: 30,
      ).corners(1, 1);
      final diag = 72.11102550927978; // sqrt(60² + 40²)
      for (final k in corners) {
        expect(haversineMetres(c, k), closeTo(diag, 0.01));
      }
      expect(haversineMetres(corners[0], corners[1]), closeTo(120, 0.05));
      expect(haversineMetres(corners[1], corners[2]), closeTo(80, 0.05));
    });
  });
}
