// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:proj4dart/proj4dart.dart' as proj4;

import 'geo_point.dart';
import 'mercator.dart';

/// A coordinate reference system that files (Shapefile `.prj`, GeoTIFF keys,
/// world files) can be expressed in, with conversion to and from WGS‑84.
///
/// Geographic WGS‑84 and Web Mercator are computed directly; everything else
/// (UTM, national grids from a `.prj`) goes through proj4dart.
abstract class Crs {
  const Crs();

  static const Crs wgs84 = _Wgs84();
  static const Crs webMercator = _WebMercatorCrs();

  /// WGS‑84 / UTM. [zone] 1..60.
  factory Crs.utm(int zone, {bool south = false}) {
    if (zone < 1 || zone > 60) throw ArgumentError.value(zone, 'zone', 'UTM zone must be 1..60');
    return _Proj4Crs(
      'WGS 84 / UTM zone $zone${south ? 'S' : 'N'}',
      '+proj=utm +zone=$zone${south ? ' +south' : ''} +datum=WGS84 +units=m +no_defs',
      epsg: (south ? 32700 : 32600) + zone,
    );
  }

  /// Built‑in EPSG codes: 4326, 3857 (and its aliases), WGS‑84 UTM
  /// 32601–32660 / 32701–32760, and CGCS2000 geographic (4490, treated as
  /// WGS‑84, which it matches to centimetres). Returns null otherwise.
  static Crs? fromEpsg(int code) {
    if (code == 4326 || code == 4490) return wgs84;
    if (code == 3857 || code == 900913 || code == 3785 || code == 102100 || code == 102113) return webMercator;
    if (code > 32600 && code <= 32660) return Crs.utm(code - 32600);
    if (code > 32700 && code <= 32760) return Crs.utm(code - 32700, south: true);
    return null;
  }

  /// Parses OGC or ESRI WKT (as found in `.prj` files) or a proj4 string.
  static Crs parse(String definition) {
    final text = definition.trim();
    if (text.isEmpty) throw const FormatException('Empty projection definition');
    final epsg = _authorityCode(text);
    if (epsg != null) {
      final known = fromEpsg(epsg);
      if (known != null) return known;
    }
    if (text.startsWith('GEOGCS') || text.startsWith('GEOGCRS')) {
      // Geographic on a WGS‑84‑compatible datum: identical for map display.
      if (RegExp(
        r'WGS[_ ]?1984|WGS[_ ]?84|CGCS[_ ]?2000|ETRS[_ ]?1989|NAD[_ ]?1983',
        caseSensitive: false,
      ).hasMatch(text)) {
        return wgs84;
      }
    }
    final utm = RegExp(r'UTM[_ ]zone[_ ](\d{1,2})([NS])', caseSensitive: false).firstMatch(text);
    if (utm != null && RegExp(r'WGS[_ ]?(19)?84', caseSensitive: false).hasMatch(text)) {
      return Crs.utm(int.parse(utm.group(1)!), south: utm.group(2)!.toUpperCase() == 'S');
    }
    try {
      return _Proj4Crs(_name(text), text, epsg: epsg);
    } catch (e) {
      throw FormatException('Unsupported projection: $e');
    }
  }

  String get name;
  int? get epsg;

  /// Projected/geographic (x, y) → WGS‑84. For geographic systems x is
  /// longitude and y latitude.
  GeoPoint toWgs84(double x, double y);

  (double, double) fromWgs84(GeoPoint p);

  bool get isGeographic => false;

  @override
  String toString() => name;

  static int? _authorityCode(String wkt) {
    // The outermost AUTHORITY / ID is the last one in WKT1 and WKT2.
    final m = RegExp(r'(?:AUTHORITY|ID)\["EPSG",\s*"?(\d+)"?\]\s*\]\s*$').firstMatch(wkt);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static String _name(String text) => RegExp(r'^\w+\["([^"]+)"').firstMatch(text)?.group(1) ?? 'Custom projection';
}

final class _Wgs84 extends Crs {
  const _Wgs84();
  @override
  String get name => 'WGS 84';
  @override
  int get epsg => 4326;
  @override
  bool get isGeographic => true;
  @override
  GeoPoint toWgs84(double x, double y) => GeoPoint(y, x);
  @override
  (double, double) fromWgs84(GeoPoint p) => (p.lon, p.lat);
}

final class _WebMercatorCrs extends Crs {
  const _WebMercatorCrs();
  @override
  String get name => 'WGS 84 / Pseudo‑Mercator';
  @override
  int get epsg => 3857;
  @override
  GeoPoint toWgs84(double x, double y) => WebMercator.fromMetres(x, y);
  @override
  (double, double) fromWgs84(GeoPoint p) => WebMercator.toMetres(p.lat, p.lon);
}

final class _Proj4Crs extends Crs {
  _Proj4Crs(this.name, String definition, {this.epsg}) : _proj = proj4.Projection.parse(definition);

  @override
  final String name;
  @override
  final int? epsg;
  final proj4.Projection _proj;
  static final _wgs = proj4.Projection.WGS84;

  @override
  GeoPoint toWgs84(double x, double y) {
    final p = _proj.transform(_wgs, proj4.Point(x: x, y: y));
    return GeoPoint(p.y, p.x);
  }

  @override
  (double, double) fromWgs84(GeoPoint p) {
    final r = _wgs.transform(_proj, proj4.Point(x: p.lon, y: p.lat));
    return (r.x, r.y);
  }
}
