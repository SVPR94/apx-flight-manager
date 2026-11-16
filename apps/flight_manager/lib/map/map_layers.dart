// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../state/map_tiles.dart';
import '../state/overlays.dart';

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lon);
GeoPoint toGeo(LatLng p) => GeoPoint(p.latitude, p.longitude);
LatLngBounds toLatLngBounds(GeoBounds b) => LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east));

/// A tapped vector feature.

/// The map's background: the chosen base map, then raster overlays, then
/// vector overlays, in the user's order. Shared by every map in the app.
///
/// Returns layers to spread into `FlutterMap.children`. Call from a build
/// method (it watches providers).
List<Widget> mapBaseLayers(WidgetRef ref) {
  final engine = ref.watch(tileEngineProvider).value;
  final base = ref.watch(currentBaseMapProvider);
  final overlays = ref.watch(overlaysProvider);
  if (engine == null) return const [];

  return [
    ServerTileLayer(key: ValueKey('base:${base.id}'), url: engine.urlTemplate(base.id), maxNativeZoom: base.maxZoom),
    for (final o in overlays.where((o) => o.spec.visible && o.spec.isRaster && !o.busy && o.spec.bounds != null))
      Opacity(
        key: ValueKey(o.spec.sourceId),
        opacity: o.spec.opacity,
        child: ServerTileLayer(
          url: engine.urlTemplate(o.spec.sourceId),
          maxNativeZoom: o.spec.maxZoom ?? 22,
          bounds: toLatLngBounds(o.spec.bounds!),
        ),
      ),
    for (final o in overlays.where((o) => o.spec.visible && o.spec.kind == OverlayKind.vector && o.layers.isNotEmpty))
      _VectorOverlay(key: ValueKey('vec:${o.spec.id}'), overlay: o),
  ];
}

/// A tile layer reading from the in‑app tile server.
///
/// Each layer owns its [NetworkTileProvider]: flutter_map's TileLayer
/// disposes its provider when the layer goes away, so a provider shared
/// between layers would die the first time the base map is switched (that
/// was the "map doesn't change" bug). The server does all caching, so
/// flutter_map's own plugin‑based cache is off.
class ServerTileLayer extends StatefulWidget {
  const ServerTileLayer({super.key, required this.url, required this.maxNativeZoom, this.bounds});
  final String url;
  final int maxNativeZoom;
  final LatLngBounds? bounds;

  @override
  State<ServerTileLayer> createState() => _ServerTileLayerState();
}

class _ServerTileLayerState extends State<ServerTileLayer> {
  // Disposed by the TileLayer itself.
  late final _provider = NetworkTileProvider(
    cachingProvider: const DisabledMapCachingProvider(),
    silenceExceptions: true,
  );

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: widget.url,
    maxNativeZoom: widget.maxNativeZoom,
    tileBounds: widget.bounds,
    tileProvider: _provider,
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
  );
}

/// Attribution line for the current base map.
Widget mapAttribution(WidgetRef ref) {
  final base = ref.watch(currentBaseMapProvider);
  return RichAttributionWidget(
    showFlutterMapAttribution: false,
    attributions: [if (base.attribution.isNotEmpty) TextSourceAttribution(base.attribution)],
  );
}

class _VectorOverlay extends StatefulWidget {
  const _VectorOverlay({super.key, required this.overlay});
  final OverlayItem overlay;

  @override
  State<_VectorOverlay> createState() => _VectorOverlayState();
}

class _VectorOverlayState extends State<_VectorOverlay> {
  // Geometry converted once per overlay version, not every frame.
  late _Shapes _shapes = _Shapes.of(widget.overlay);

  @override
  void didUpdateWidget(_VectorOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.overlay.layers, widget.overlay.layers) ||
        old.overlay.spec.opacity != widget.overlay.spec.opacity) {
      _shapes = _Shapes.of(widget.overlay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shapes;
    // Display only: clicks go through to the map (fence points, waypoints).
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (s.polygons.isNotEmpty) PolygonLayer(polygons: s.polygons),
          if (s.lines.isNotEmpty) PolylineLayer(polylines: s.lines),
          if (s.points.isNotEmpty) CircleLayer(circles: s.points),
        ],
      ),
    );
  }
}

final class _Shapes {
  _Shapes(this.polygons, this.lines, this.points);
  final List<Polygon> polygons;
  final List<Polyline> lines;
  final List<CircleMarker> points;

  factory _Shapes.of(OverlayItem o) {
    final colour = Color(o.spec.colour);
    final a = o.spec.opacity;
    final polygons = <Polygon>[];
    final lines = <Polyline>[];
    final points = <CircleMarker>[];
    for (final layer in o.layers) {
      for (final f in layer.features) {
        switch (f.geometry) {
          case VectorPolygons(polygons: final rings):
            for (final p in rings) {
              polygons.add(
                Polygon(
                  points: [for (final v in p.outer) toLatLng(v)],
                  holePointsList: [
                    for (final h in p.holes) [for (final v in h) toLatLng(v)],
                  ],
                  color: colour.withValues(alpha: 0.16 * a),
                  borderColor: colour.withValues(alpha: a),
                  borderStrokeWidth: 2,
                ),
              );
            }
          case VectorLines(lines: final paths):
            for (final l in paths) {
              lines.add(
                Polyline(
                  points: [for (final v in l) toLatLng(v)],
                  color: colour.withValues(alpha: a),
                  strokeWidth: 2.5,
                ),
              );
            }
          case VectorPoints(points: final pts):
            for (final p in pts) {
              points.add(
                CircleMarker(
                  point: toLatLng(p),
                  radius: 5,
                  color: colour.withValues(alpha: 0.85 * a),
                  borderColor: Colors.white.withValues(alpha: a),
                  borderStrokeWidth: 1.5,
                ),
              );
            }
        }
      }
    }
    return _Shapes(polygons, lines, points);
  }
}
