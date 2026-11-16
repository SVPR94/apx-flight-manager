// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

/// A WGS‑84 position in degrees. apx_geo keeps its own type so the package
/// stays free of Flutter; the app converts to `LatLng` at the map boundary.
final class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint(${lat.toStringAsFixed(7)}, ${lon.toStringAsFixed(7)})';
}

/// A latitude/longitude box. Does not handle boxes crossing the antimeridian;
/// nothing APX flies is that large.
final class GeoBounds {
  const GeoBounds(this.south, this.west, this.north, this.east);

  factory GeoBounds.around(Iterable<GeoPoint> points) {
    var s = double.infinity, w = double.infinity, n = -double.infinity, e = -double.infinity;
    for (final p in points) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    if (s > n) throw ArgumentError('GeoBounds.around needs at least one point');
    return GeoBounds(s, w, n, e);
  }

  final double south, west, north, east;

  GeoPoint get center => GeoPoint((south + north) / 2, (west + east) / 2);

  bool contains(GeoPoint p) => p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  bool intersects(GeoBounds o) => o.west <= east && o.east >= west && o.south <= north && o.north >= south;

  GeoBounds union(GeoBounds o) =>
      GeoBounds(math.min(south, o.south), math.min(west, o.west), math.max(north, o.north), math.max(east, o.east));

  Map<String, double> toJson() => {'south': south, 'west': west, 'north': north, 'east': east};

  factory GeoBounds.fromJson(Map<String, Object?> j) => GeoBounds(
    (j['south'] as num).toDouble(),
    (j['west'] as num).toDouble(),
    (j['north'] as num).toDouble(),
    (j['east'] as num).toDouble(),
  );

  @override
  String toString() => 'GeoBounds($south, $west, $north, $east)';
}

const _earthRadius = 6371008.8;

/// Great‑circle distance in metres.
double haversineMetres(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat), dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

/// The point [metres] from [from] along [bearingDeg] (spherical earth; exact
/// enough for placing images a few kilometres across).
GeoPoint destination(GeoPoint from, double bearingDeg, double metres) {
  final d = metres / _earthRadius, b = _rad(bearingDeg), la = _rad(from.lat), lo = _rad(from.lon);
  final la2 = math.asin(math.sin(la) * math.cos(d) + math.cos(la) * math.sin(d) * math.cos(b));
  final lo2 = lo + math.atan2(math.sin(b) * math.sin(d) * math.cos(la), math.cos(d) - math.sin(la) * math.sin(la2));
  return GeoPoint(_deg(la2), (_deg(lo2) + 540) % 360 - 180);
}

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Initial great‑circle bearing from [a] to [b], degrees clockwise from north
/// in [0, 360).
double bearingDeg(GeoPoint a, GeoPoint b) {
  final la1 = _rad(a.lat), la2 = _rad(b.lat), dLon = _rad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// A flat east/north metre frame around [origin] (equirectangular). Plenty for
/// laying out survey lines over a few kilometres; convert back with [toGeo].
final class LocalFrame {
  LocalFrame(this.origin) : _cos = math.cos(_rad(origin.lat));

  final GeoPoint origin;
  final double _cos;
  static const _r = 6378137.0;

  (double, double) toLocal(GeoPoint p) => (_rad(p.lon - origin.lon) * _r * _cos, _rad(p.lat - origin.lat) * _r);

  GeoPoint toGeo(double x, double y) => GeoPoint(origin.lat + _deg(y / _r), origin.lon + _deg(x / (_r * _cos)));
}
