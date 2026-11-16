// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../geo/crs.dart';
import '../geo/geo_point.dart';

/// Geometry of one vector feature, in WGS‑84.
sealed class VectorGeometry {
  const VectorGeometry();
  Iterable<GeoPoint> get vertices;
}

final class VectorPoints extends VectorGeometry {
  const VectorPoints(this.points);
  final List<GeoPoint> points;
  @override
  Iterable<GeoPoint> get vertices => points;
}

final class VectorLines extends VectorGeometry {
  const VectorLines(this.lines);
  final List<List<GeoPoint>> lines;
  @override
  Iterable<GeoPoint> get vertices => lines.expand((l) => l);
}

final class VectorPolygon {
  const VectorPolygon(this.outer, this.holes);
  final List<GeoPoint> outer;
  final List<List<GeoPoint>> holes;
}

final class VectorPolygons extends VectorGeometry {
  const VectorPolygons(this.polygons);
  final List<VectorPolygon> polygons;
  @override
  Iterable<GeoPoint> get vertices => polygons.expand((p) => p.outer);
}

final class VectorFeature {
  const VectorFeature(this.geometry, this.attributes);
  final VectorGeometry geometry;
  final Map<String, Object?> attributes;
}

/// A layer read from a Shapefile, already in WGS‑84.
final class VectorLayer {
  VectorLayer({
    required this.name,
    required this.features,
    required this.fields,
    required this.crsName,
    required this.skipped,
  });

  final String name;
  final List<VectorFeature> features;
  final List<String> fields;

  /// The source projection, for display.
  final String crsName;

  /// Records that could not be used (null shapes, MultiPatch).
  final int skipped;

  GeoBounds? get bounds {
    final all = features.expand((f) => f.geometry.vertices);
    return all.isEmpty ? null : GeoBounds.around(all);
  }
}

/// ESRI Shapefile reader (.shp + optional .dbf/.prj/.cpg, or a .zip of them).
abstract final class Shapefile {
  /// Reads one shapefile. Without a `.prj`, coordinates must be geographic
  /// WGS‑84 (checked against the file's bounding box).
  static VectorLayer read({required String name, required Uint8List shp, Uint8List? dbf, String? prj, String? cpg}) {
    final crs = _crsFor(shp, prj);
    final records = _readShp(shp, crs);
    final (fields, rows) = dbf == null ? (const <String>[], const <Map<String, Object?>>[]) : _readDbf(dbf, cpg);
    final features = <VectorFeature>[];
    var skipped = 0;
    for (var i = 0; i < records.length; i++) {
      final g = records[i];
      if (g == null) {
        skipped++;
        continue;
      }
      features.add(VectorFeature(g, i < rows.length ? rows[i] : const {}));
    }
    return VectorLayer(name: name, features: features, fields: fields, crsName: crs.name, skipped: skipped);
  }

  /// Reads every shapefile inside a zip archive.
  static List<VectorLayer> readZip(Uint8List zip) {
    final archive = ZipDecoder().decodeBytes(zip);
    final byName = {for (final f in archive.files.where((f) => f.isFile)) f.name.toLowerCase(): f};
    final layers = <VectorLayer>[];
    for (final entry in byName.entries.where((e) => e.key.endsWith('.shp'))) {
      final base = entry.key.substring(0, entry.key.length - 4);
      Uint8List? part(String ext) => byName['$base.$ext']?.readBytes();
      final prj = part('prj'), cpg = part('cpg');
      final display = entry.value.name.split('/').last;
      layers.add(
        read(
          name: display.substring(0, display.length - 4),
          shp: entry.value.readBytes()!,
          dbf: part('dbf'),
          prj: prj == null ? null : latin1.decode(prj),
          cpg: cpg == null ? null : latin1.decode(cpg),
        ),
      );
    }
    if (layers.isEmpty) throw const FormatException('The zip contains no .shp file');
    return layers;
  }

  static Crs _crsFor(Uint8List shp, String? prj) {
    if (prj != null && prj.trim().isNotEmpty) return Crs.parse(prj);
    if (shp.length < 100) throw const FormatException('Not a shapefile (too short)');
    final d = ByteData.sublistView(shp);
    final xmin = d.getFloat64(36, Endian.little), ymin = d.getFloat64(44, Endian.little);
    final xmax = d.getFloat64(52, Endian.little), ymax = d.getFloat64(60, Endian.little);
    if ([xmin, xmax].every((v) => v.abs() <= 180) && [ymin, ymax].every((v) => v.abs() <= 90)) return Crs.wgs84;
    throw const FormatException(
      'This shapefile is in projected coordinates but has no .prj file. Add the .prj (same name).',
    );
  }

  static List<VectorGeometry?> _readShp(Uint8List bytes, Crs crs) {
    if (bytes.length < 100) throw const FormatException('Not a shapefile (too short)');
    final d = ByteData.sublistView(bytes);
    if (d.getInt32(0, Endian.big) != 9994) throw const FormatException('Not a shapefile (bad file code)');
    final end = (d.getInt32(24, Endian.big) * 2).clamp(100, bytes.length);
    final out = <VectorGeometry?>[];
    var o = 100;
    while (o + 8 <= end) {
      final len = d.getInt32(o + 4, Endian.big) * 2;
      final c = o + 8;
      o = c + len;
      if (len < 4 || o > end) {
        if (o > end) break;
        out.add(null);
        continue;
      }
      out.add(_shape(d, c, crs));
    }
    return out;
  }

  static GeoPoint _pt(ByteData d, int o, Crs crs) =>
      crs.toWgs84(d.getFloat64(o, Endian.little), d.getFloat64(o + 8, Endian.little));

  static VectorGeometry? _shape(ByteData d, int c, Crs crs) {
    final type = d.getInt32(c, Endian.little);
    switch (type) {
      case 1 || 11 || 21:
        return VectorPoints([_pt(d, c + 4, crs)]);
      case 8 || 18 || 28:
        final n = d.getInt32(c + 36, Endian.little);
        return VectorPoints([for (var i = 0; i < n; i++) _pt(d, c + 40 + i * 16, crs)]);
      case 3 || 13 || 23 || 5 || 15 || 25:
        final parts = d.getInt32(c + 36, Endian.little), n = d.getInt32(c + 40, Endian.little);
        final starts = [for (var i = 0; i < parts; i++) d.getInt32(c + 44 + i * 4, Endian.little), n];
        final p0 = c + 44 + parts * 4;
        final rings = [
          for (var i = 0; i < parts; i++) [for (var k = starts[i]; k < starts[i + 1]; k++) _pt(d, p0 + k * 16, crs)],
        ];
        if (type % 10 == 3) return VectorLines(rings);
        return VectorPolygons(
          _assemble(rings, [
            for (var i = 0; i < parts; i++)
              _signedArea([
                for (var k = starts[i]; k < starts[i + 1]; k++)
                  (d.getFloat64(p0 + k * 16, Endian.little), d.getFloat64(p0 + k * 16 + 8, Endian.little)),
              ]),
          ]),
        );
      default:
        return null; // null shape, MultiPatch
    }
  }

  /// Shapefile rings: outer rings run clockwise (negative area), holes
  /// counter‑clockwise. Each hole joins the outer ring that contains it.
  static List<VectorPolygon> _assemble(List<List<GeoPoint>> rings, List<double> areas) {
    final outers = <(List<GeoPoint>, List<List<GeoPoint>>)>[];
    final holes = <List<GeoPoint>>[];
    for (var i = 0; i < rings.length; i++) {
      if (rings[i].length < 3) continue;
      if (areas[i] <= 0) {
        outers.add((rings[i], <List<GeoPoint>>[]));
      } else {
        holes.add(rings[i]);
      }
    }
    for (final h in holes) {
      final owner = outers.where((o) => _contains(o.$1, h.first)).firstOrNull;
      if (owner != null) {
        owner.$2.add(h);
      } else {
        outers.add((h, <List<GeoPoint>>[])); // wrongly wound outer ring
      }
    }
    return [for (final (o, hs) in outers) VectorPolygon(o, hs)];
  }

  static double _signedArea(List<(double, double)> r) {
    var a = 0.0;
    for (var i = 0; i < r.length - 1; i++) {
      a += r[i].$1 * r[i + 1].$2 - r[i + 1].$1 * r[i].$2;
    }
    return a / 2;
  }

  static bool _contains(List<GeoPoint> ring, GeoPoint p) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.lat > p.lat) != (b.lat > p.lat) && p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon) {
        inside = !inside;
      }
    }
    return inside;
  }

  static (List<String>, List<Map<String, Object?>>) _readDbf(Uint8List bytes, String? cpg) {
    if (bytes.length < 32) return (const [], const []);
    final d = ByteData.sublistView(bytes);
    final count = d.getUint32(4, Endian.little),
        headerLen = d.getUint16(8, Endian.little),
        recLen = d.getUint16(10, Endian.little);
    final fields = <(String, String, int)>[];
    for (var o = 32; o + 32 <= headerLen && bytes[o] != 0x0D; o += 32) {
      final raw = bytes.sublist(o, o + 11);
      final z = raw.indexOf(0);
      fields.add((
        latin1.decode(z < 0 ? raw : raw.sublist(0, z)).trim(),
        String.fromCharCode(bytes[o + 11]),
        bytes[o + 16],
      ));
    }
    final decode = _decoder(cpg, bytes.length > 29 ? bytes[29] : 0);
    final rows = <Map<String, Object?>>[];
    for (var r = 0; r < count; r++) {
      final o = headerLen + r * recLen;
      if (o + recLen > bytes.length) break;
      if (bytes[o] == 0x2A) {
        rows.add(const {}); // deleted record keeps its slot so shapes stay aligned
        continue;
      }
      final row = <String, Object?>{};
      var p = o + 1;
      for (final (name, type, len) in fields) {
        final text = decode(bytes.sublist(p, p + len)).trim();
        p += len;
        row[name] = switch (type) {
          'N' || 'F' => text.isEmpty ? null : num.tryParse(text),
          'L' => text.isEmpty || text == '?' ? null : 'TtYy'.contains(text[0]),
          'D' when text.length == 8 => '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6)}',
          _ => text,
        };
      }
      rows.add(row);
    }
    return ([for (final f in fields) f.$1], rows);
  }

  static String Function(List<int>) _decoder(String? cpg, int ldid) {
    final name = cpg?.trim().toUpperCase() ?? '';
    final latin =
        name.contains('1252') || name.contains('8859') || name.contains('LATIN') || (name.isEmpty && ldid == 0x57);
    if (latin) return latin1.decode;
    // UTF‑8 when declared or unknown; fall back to Latin‑1 for invalid bytes.
    return (b) {
      try {
        return utf8.decode(b);
      } on FormatException {
        return latin1.decode(b);
      }
    };
  }
}
