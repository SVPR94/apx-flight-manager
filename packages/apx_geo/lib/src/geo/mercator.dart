// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'geo_point.dart';

/// Side of every tile the map draws, in pixels.
const tileSize = 256;

/// A slippy‑map tile address (Web Mercator, y down from the north).
final class TileId {
  const TileId(this.z, this.x, this.y);

  final int z, x, y;

  /// Bing‑style quadkey, used by some custom sources.
  String get quadKey {
    final b = StringBuffer();
    for (var i = z; i > 0; i--) {
      final mask = 1 << (i - 1);
      b.write((x & mask != 0 ? 1 : 0) + (y & mask != 0 ? 2 : 0));
    }
    return b.toString();
  }

  TileId get parent => TileId(z - 1, x >> 1, y >> 1);

  List<TileId> get children => [
    TileId(z + 1, 2 * x, 2 * y),
    TileId(z + 1, 2 * x + 1, 2 * y),
    TileId(z + 1, 2 * x, 2 * y + 1),
    TileId(z + 1, 2 * x + 1, 2 * y + 1),
  ];

  bool get isValid => z >= 0 && z <= 30 && x >= 0 && y >= 0 && x < (1 << z) && y < (1 << z);

  GeoBounds get bounds {
    final n = WebMercator.pixelsAt(z);
    return GeoBounds(
      WebMercator.yToLat((y + 1) * tileSize / n * 1.0),
      WebMercator.xToLon(x * tileSize / n),
      WebMercator.yToLat(y * tileSize / n),
      WebMercator.xToLon((x + 1) * tileSize / n),
    );
  }

  @override
  bool operator ==(Object other) => other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// Spherical (EPSG:3857) Web Mercator in normalised units: x and y run 0..1
/// across the world, y down from the north. Multiply by [pixelsAt] for pixels.
abstract final class WebMercator {
  static const maxLatitude = 85.05112877980659;
  static const earthRadius = 6378137.0;
  static const halfCircumference = math.pi * earthRadius;

  static double pixelsAt(int z) => tileSize * math.pow(2, z).toDouble();

  static double lonToX(double lon) => (lon + 180) / 360;

  static double latToY(double lat) {
    final s = math.sin(lat.clamp(-maxLatitude, maxLatitude) * math.pi / 180);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  static double xToLon(double x) => x * 360 - 180;

  static double yToLat(double y) => 90 - 360 * math.atan(math.exp((y - 0.5) * 2 * math.pi)) / math.pi;

  /// Global pixel position of [p] at zoom [z].
  static (double, double) toPixel(GeoPoint p, int z) {
    final n = pixelsAt(z);
    return (lonToX(p.lon) * n, latToY(p.lat) * n);
  }

  static GeoPoint fromPixel(double px, double py, int z) {
    final n = pixelsAt(z);
    return GeoPoint(yToLat(py / n), xToLon(px / n));
  }

  /// EPSG:3857 metres.
  static (double, double) toMetres(double lat, double lon) {
    final x = lon * math.pi / 180 * earthRadius;
    final la = lat.clamp(-maxLatitude, maxLatitude) * math.pi / 180;
    return (x, earthRadius * math.log(math.tan(math.pi / 4 + la / 2)));
  }

  static GeoPoint fromMetres(double x, double y) => GeoPoint(
    (2 * math.atan(math.exp(y / earthRadius)) - math.pi / 2) * 180 / math.pi,
    x / earthRadius * 180 / math.pi,
  );

  /// Ground metres per pixel at [lat] and zoom [z].
  static double metresPerPixel(double lat, int z) =>
      math.cos(lat * math.pi / 180) * 2 * halfCircumference / pixelsAt(z);

  static TileId tileAt(GeoPoint p, int z) {
    final (px, py) = toPixel(p, z);
    final max = (1 << z) - 1;
    return TileId(z, (px / tileSize).floor().clamp(0, max), (py / tileSize).floor().clamp(0, max));
  }

  /// Every tile at zoom [z] that touches [b].
  static Iterable<TileId> tilesCovering(GeoBounds b, int z) sync* {
    final a = tileAt(GeoPoint(b.north, b.west), z), c = tileAt(GeoPoint(b.south, b.east), z);
    for (var y = a.y; y <= c.y; y++) {
      for (var x = a.x; x <= c.x; x++) {
        yield TileId(z, x, y);
      }
    }
  }

  static int countTiles(GeoBounds b, int minZoom, int maxZoom) {
    var n = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final a = tileAt(GeoPoint(b.north, b.west), z), c = tileAt(GeoPoint(b.south, b.east), z);
      n += (c.x - a.x + 1) * (c.y - a.y + 1);
    }
    return n;
  }
}
