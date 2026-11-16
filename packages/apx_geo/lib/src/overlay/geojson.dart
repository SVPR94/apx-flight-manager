// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:typed_data';

import '../geo/crs.dart';
import '../geo/geo_point.dart';
import 'shapefile.dart';

/// GeoJSON reader (RFC 7946, plus the 2008 `crs` member written by GDAL/QGIS)
/// into the same [VectorLayer] model as Shapefiles.
///
/// Accepts a FeatureCollection, a single Feature, or a bare geometry. All
/// geometry types are read; a GeometryCollection becomes one feature per
/// geometry kind (points / lines / polygons) sharing the properties.
/// Features without a usable geometry are counted in [VectorLayer.skipped].
abstract final class GeoJson {
  static VectorLayer read({required String name, required Uint8List bytes}) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (root is! Map) throw const FormatException('Not a GeoJSON object');
    final type = root['type'];

    final List<Map> features;
    if (type == 'FeatureCollection') {
      final fs = root['features'];
      if (fs is! List) throw const FormatException('FeatureCollection without a "features" list');
      features = [
        for (final f in fs)
          if (f is Map) f,
      ];
    } else if (type == 'Feature') {
      features = [root];
    } else if (_geometryTypes.contains(type)) {
      features = [
        {'type': 'Feature', 'geometry': root, 'properties': null},
      ];
    } else {
      throw FormatException('Not GeoJSON (type "${type ?? 'missing'}")');
    }

    final crs = _crsFor(root['crs'], features);
    final out = <VectorFeature>[];
    final fields = <String>{};
    var skipped = 0;
    for (final f in features) {
      final attributes = _attributes(f);
      fields.addAll(attributes.keys);
      final geometries = _geometries(f['geometry'], crs);
      if (geometries.isEmpty) {
        skipped++;
        continue;
      }
      for (final g in geometries) {
        out.add(VectorFeature(g, attributes));
      }
    }
    final layerName = root['name'];
    return VectorLayer(
      name: layerName is String && layerName.trim().isNotEmpty ? layerName.trim() : name,
      features: out,
      fields: fields.toList(),
      crsName: crs.name,
      skipped: skipped,
    );
  }

  static const _geometryTypes = {
    'Point',
    'MultiPoint',
    'LineString',
    'MultiLineString',
    'Polygon',
    'MultiPolygon',
    'GeometryCollection',
  };

  /// RFC 7946 data is always WGS‑84 longitude/latitude. Older files may name
  /// another CRS (`"crs": {"type": "name", "properties": {"name":
  /// "urn:ogc:def:crs:EPSG::32643"}}`); those with a known EPSG code are
  /// reprojected.
  static Crs _crsFor(Object? member, List<Map> features) {
    String? named;
    if (member is Map && member['properties'] is Map) {
      final n = (member['properties'] as Map)['name'];
      if (n is String) named = n;
    }
    if (named != null) {
      final upper = named.toUpperCase();
      if (upper.contains('CRS84') || upper.contains('CRS:84')) return Crs.wgs84;
      final code = RegExp(r'EPSG:(?:[\d.]*:)?(\d+)$').firstMatch(upper)?.group(1);
      final crs = code == null ? null : Crs.fromEpsg(int.parse(code));
      if (crs != null) return crs;
      if (_looksGeographic(features)) return Crs.wgs84;
      throw FormatException(
        'This GeoJSON uses the coordinate system "$named", which isn\'t supported. '
        'Export it as WGS 84 (EPSG:4326), or as WGS 84 / UTM or Web Mercator.',
      );
    }
    if (_looksGeographic(features)) return Crs.wgs84;
    throw const FormatException(
      'This GeoJSON has projected coordinates but doesn\'t say which projection. '
      'Export it as WGS 84 (EPSG:4326), as GeoJSON requires.',
    );
  }

  /// Every position within ±180° / ±90° (checks the first few per feature).
  static bool _looksGeographic(List<Map> features) {
    bool ok(Object? c, int depth) {
      if (depth > 6 || c is! List || c.isEmpty) return true;
      if (c.first is num) {
        if (c.length < 2 || c[1] is! num) return true;
        return (c[0] as num).abs() <= 180 && (c[1] as num).abs() <= 90;
      }
      return c.take(8).every((e) => ok(e, depth + 1));
    }

    bool geometryOk(Object? g) {
      if (g is! Map) return true;
      if (g['type'] == 'GeometryCollection') {
        final gs = g['geometries'];
        return gs is! List || gs.every(geometryOk);
      }
      return ok(g['coordinates'], 0);
    }

    return features.every((f) => geometryOk(f['geometry']));
  }

  static Map<String, Object?> _attributes(Map f) {
    final out = <String, Object?>{};
    final id = f['id'];
    final props = f['properties'];
    if (id != null && !(props is Map && props.containsKey('id'))) out['id'] = id;
    if (props is Map) {
      for (final e in props.entries) {
        final v = e.value;
        // Nested objects/arrays are shown as their JSON text.
        out['${e.key}'] = v == null || v is num || v is String || v is bool ? v : jsonEncode(v);
      }
    }
    return out;
  }

  /// The feature's geometry, grouped by kind; empty when unusable.
  static List<VectorGeometry> _geometries(Object? g, Crs crs) {
    final points = <GeoPoint>[];
    final lines = <List<GeoPoint>>[];
    final polygons = <VectorPolygon>[];
    _collect(g, crs, points, lines, polygons, 0);
    return [
      if (points.isNotEmpty) VectorPoints(points),
      if (lines.isNotEmpty) VectorLines(lines),
      if (polygons.isNotEmpty) VectorPolygons(polygons),
    ];
  }

  static void _collect(
    Object? g,
    Crs crs,
    List<GeoPoint> points,
    List<List<GeoPoint>> lines,
    List<VectorPolygon> polygons,
    int depth,
  ) {
    if (g is! Map || depth > 8) return;
    final c = g['coordinates'];
    switch (g['type']) {
      case 'Point':
        final p = _position(c, crs);
        if (p != null) points.add(p);
      case 'MultiPoint':
        if (c is List) points.addAll(c.map((e) => _position(e, crs)).whereType<GeoPoint>());
      case 'LineString':
        final l = _line(c, crs, 2);
        if (l != null) lines.add(l);
      case 'MultiLineString':
        if (c is List) lines.addAll(c.map((e) => _line(e, crs, 2)).whereType<List<GeoPoint>>());
      case 'Polygon':
        final p = _polygon(c, crs);
        if (p != null) polygons.add(p);
      case 'MultiPolygon':
        if (c is List) polygons.addAll(c.map((e) => _polygon(e, crs)).whereType<VectorPolygon>());
      case 'GeometryCollection':
        final gs = g['geometries'];
        if (gs is List) {
          for (final m in gs) {
            _collect(m, crs, points, lines, polygons, depth + 1);
          }
        }
    }
  }

  static GeoPoint? _position(Object? c, Crs crs) {
    if (c is! List || c.length < 2 || c[0] is! num || c[1] is! num) return null;
    final x = (c[0] as num).toDouble(), y = (c[1] as num).toDouble();
    if (!x.isFinite || !y.isFinite) return null;
    return crs.toWgs84(x, y);
  }

  static List<GeoPoint>? _line(Object? c, Crs crs, int min) {
    if (c is! List) return null;
    final pts = c.map((e) => _position(e, crs)).whereType<GeoPoint>().toList();
    return pts.length >= min ? pts : null;
  }

  /// First ring is the outline, the rest are holes (RFC 7946 §3.1.6).
  static VectorPolygon? _polygon(Object? c, Crs crs) {
    if (c is! List || c.isEmpty) return null;
    final outer = _line(c.first, crs, 3);
    if (outer == null) return null;
    return VectorPolygon(outer, [for (final r in c.skip(1)) ?_line(r, crs, 3)]);
  }
}
