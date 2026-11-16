// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Represents a computed directional arrow along a flight path segment.
class PathArrow {
  const PathArrow({
    required this.midpoint,
    required this.bearingDeg,
    required this.color,
  });

  /// The geographic midpoint coordinate of the segment.
  final LatLng midpoint;

  /// The geodesic bearing of travel in degrees clockwise from north [0, 360).
  final double bearingDeg;

  /// The display color of the direction arrow.
  final Color color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathArrow &&
          runtimeType == other.runtimeType &&
          midpoint == other.midpoint &&
          bearingDeg == other.bearingDeg &&
          color == other.color;

  @override
  int get hashCode => Object.hash(midpoint, bearingDeg, color);

  @override
  String toString() =>
      'PathArrow(midpoint: $midpoint, bearingDeg: $bearingDeg, color: $color)';
}

/// Renders an aerodynamic directional chevron with dark outer casing.
class DirectionArrow extends StatelessWidget {
  const DirectionArrow({
    super.key,
    required this.color,
    this.size = 16.0,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DirectionArrowPainter(color: color),
    );
  }
}

class _DirectionArrowPainter extends CustomPainter {
  const _DirectionArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Aerodynamic chevron geometry pointing North (0°)
    final path = Path()
      ..moveTo(w * 0.5, 0.0)
      ..lineTo(w, h)
      ..lineTo(w * 0.5, h * 0.65)
      ..lineTo(0.0, h)
      ..close();

    // Dark outer casing for high visibility over bright tiles, terrain, and satellite imagery
    final casingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, w * 0.16)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xCC000000);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    canvas.drawPath(path, casingPaint);
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Computes directional arrows along path segments.
///
/// Filters out segments shorter than [minDistanceMeters] on the ground or shorter
/// than [minScreenPixels] on screen (when [camera] is available) to avoid visual clutter.
List<PathArrow> computePathArrows(
  List<LatLng> points, {
  required Color color,
  double minDistanceMeters = 25.0,
  MapCamera? camera,
  double minScreenPixels = 45.0,
}) {
  if (points.length < 2) return const [];
  final arrows = <PathArrow>[];

  for (var i = 0; i < points.length - 1; i++) {
    final p1 = points[i];
    final p2 = points[i + 1];
    final g1 = GeoPoint(p1.latitude, p1.longitude);
    final g2 = GeoPoint(p2.latitude, p2.longitude);

    final distM = haversineMetres(g1, g2);
    if (distM < minDistanceMeters) continue;

    if (camera != null) {
      final o1 = camera.latLngToScreenOffset(p1);
      final o2 = camera.latLngToScreenOffset(p2);
      if ((o2 - o1).distance < minScreenPixels) continue;
    }

    final mid = LatLng(
      (p1.latitude + p2.latitude) / 2.0,
      (p1.longitude + p2.longitude) / 2.0,
    );
    final bearing = bearingDeg(g1, g2);

    arrows.add(PathArrow(midpoint: mid, bearingDeg: bearing, color: color));
  }
  return arrows;
}

/// A FlutterMap layer widget that renders directional chevrons along path runs.
class FlightPathArrowsLayer extends StatelessWidget {
  const FlightPathArrowsLayer({
    super.key,
    required this.runs,
    this.minDistanceMeters = 25.0,
    this.minScreenPixels = 45.0,
    this.arrowSize = 16.0,
  });

  /// The path runs to render arrows for: each tuple contains a list of points
  /// and the corresponding line color.
  final List<(List<LatLng>, Color)> runs;

  /// Minimum distance in meters for a path segment to show an arrow.
  final double minDistanceMeters;

  /// Minimum screen distance in logical pixels for a path segment to show an arrow.
  final double minScreenPixels;

  /// Bounding size of the arrow marker in logical pixels.
  final double arrowSize;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.maybeOf(context);
    final markers = <Marker>[];

    for (final (pts, color) in runs) {
      if (pts.length < 2) continue;
      final arrows = computePathArrows(
        pts,
        color: color,
        minDistanceMeters: minDistanceMeters,
        camera: camera,
        minScreenPixels: minScreenPixels,
      );
      for (final a in arrows) {
        markers.add(
          Marker(
            point: a.midpoint,
            width: arrowSize,
            height: arrowSize,
            alignment: Alignment.center,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: a.bearingDeg * math.pi / 180.0,
                child: DirectionArrow(color: a.color, size: arrowSize),
              ),
            ),
          ),
        );
      }
    }

    if (markers.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: markers);
  }
}
